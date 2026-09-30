package store

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func open(t *testing.T) *Store {
	t.Helper()
	s, err := Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestReserveLimits(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	now := time.Unix(1_800_000_000, 0)
	lim := Limits{PerUser: 2, Window: 24 * time.Hour, MaxActive: 2, StaleAfter: 3 * time.Hour}

	r1, err := s.Reserve(ctx, "a", 0, "implement", "", lim, now)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.Reserve(ctx, "b", 0, "implement", "", lim, now.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	// Past the cap, runs wait instead of being refused.
	w, err := s.Reserve(ctx, "c", 0, "implement", "", lim, now)
	if err != nil || w.Status != RunWaiting {
		t.Fatalf("want a waiting run, got %+v %v", w, err)
	}
	// A finished run frees its active slot but still counts for its user.
	if err := s.SetRunStatus(ctx, r1.ID, RunCompleted, "success", 9, "u", now); err != nil {
		t.Fatal(err)
	}
	// A slot is free, but a run is already waiting for it: this one waits behind it.
	r4, err := s.Reserve(ctx, "a", 0, "implement", "", lim, now.Add(2*time.Minute))
	if err != nil || r4.Status != RunWaiting {
		t.Fatalf("want a waiting run, got %+v %v", r4, err)
	}
	var le *LimitError
	_, err = s.Reserve(ctx, "a", 0, "implement", "", lim, now.Add(3*time.Minute))
	if !errors.As(err, &le) || !le.Retry.Equal(now.Add(24*time.Hour)) {
		t.Fatalf("want per-user limit retrying at +24h, got %v %+v", err, le)
	}
	if n, err := s.WaitingPosition(ctx, r4.ID); err != nil || n != 2 {
		t.Fatalf("position %d %v", n, err)
	}
	// Waiting runs without a job (their issue is still being opened) are skipped.
	if _, err := s.StartWaiting(ctx, lim, now); !errors.Is(err, ErrNotFound) {
		t.Fatalf("started a run without a job: %v", err)
	}
	for _, r := range []Run{w, r4} {
		if _, err := s.CreateJob(ctx, Job{Issue: int(r.ID), Title: "t", ChannelID: "c", RequesterID: r.UserID, RequesterName: "U"}, r.ID, now); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.StartWaiting(ctx, lim, now)
	if err != nil || got.ID != w.ID || got.Status != RunReserved {
		t.Fatalf("started %+v %v", got, err)
	}
	if _, err := s.StartWaiting(ctx, lim, now); !errors.Is(err, ErrNotFound) {
		t.Fatalf("started past the cap: %v", err)
	}
	// Runs stuck active past StaleAfter stop counting toward the cap.
	later := now.Add(4 * time.Hour)
	if got, err := s.StartWaiting(ctx, lim, later); err != nil || got.ID != r4.ID {
		t.Fatalf("stale runs still counted: %+v %v", got, err)
	}
	if r, err := s.Reserve(ctx, "c", 0, "implement", "", lim, later); err != nil || r.Status != RunReserved {
		t.Fatalf("want a reserved run, got %+v %v", r, err)
	}
	// And the window rolls.
	if _, err := s.Reserve(ctx, "a", 0, "implement", "", Limits{PerUser: 2, Window: 24 * time.Hour, MaxActive: 5, StaleAfter: time.Hour}, now.Add(25*time.Hour)); err != nil {
		t.Fatalf("window did not roll: %v", err)
	}
}

func TestJobsAndRuns(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	now := time.Unix(1_800_000_000, 0)
	r, err := s.Reserve(ctx, "u", 0, "implement", "", Limits{Window: time.Hour}, now)
	if err != nil {
		t.Fatal(err)
	}
	j, err := s.CreateJob(ctx, Job{Issue: 3, Title: "t", ChannelID: "c", RequesterID: "u", RequesterName: "U"}, r.ID, now)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.SetThread(ctx, j.ID, "th", now); err != nil {
		t.Fatal(err)
	}
	if err := s.SetPR(ctx, j.ID, 4, now); err != nil {
		t.Fatal(err)
	}
	for _, n := range []int{3, 4} {
		got, err := s.JobByNumber(ctx, n)
		if err != nil || got.ID != j.ID || got.ThreadID != "th" || got.PR != 4 || got.State != JobOpen {
			t.Errorf("JobByNumber(%d) = %+v %v", n, got, err)
		}
	}
	active, err := s.ActiveRunForJob(ctx, j.ID)
	if err != nil || active.ID != r.ID {
		t.Fatalf("active run %+v %v", active, err)
	}
	s.SetRunStatus(ctx, r.ID, RunInProgress, "", 11, "url", now)
	s.SetRunStatus(ctx, r.ID, RunCompleted, "success", 0, "", now)
	got, _ := s.RunByID(ctx, r.ID)
	if got.WorkflowRunID != 11 || got.RunURL != "url" || got.Conclusion != "success" {
		t.Errorf("run details lost: %+v", got)
	}
	if _, err := s.ActiveRunForJob(ctx, j.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("finished run still active: %v", err)
	}
}

func TestJobHarnessRoundTrip(t *testing.T) {
	for _, harness := range []string{"codex", "claude", "pi", ""} {
		t.Run("harness="+harness, func(t *testing.T) {
			model := ""
			if harness == "pi" {
				model = "openrouter/moonshotai/kimi-k3"
			}
			ctx := context.Background()
			now := time.Unix(1_800_000_000, 0)
			path := filepath.Join(t.TempDir(), "jobs.db")
			s, err := Open(path)
			if err != nil {
				t.Fatal(err)
			}
			defer func() {
				if s != nil {
					s.Close()
				}
			}()
			r, err := s.Reserve(ctx, "u", 0, "implement", "", Limits{}, now)
			if err != nil {
				t.Fatal(err)
			}
			j, err := s.CreateJob(ctx, Job{Issue: 3, Title: "t", ChannelID: "c", RequesterID: "u", RequesterName: "U", Harness: harness, Model: model}, r.ID, now)
			if err != nil || j.Harness != harness || j.Model != model {
				t.Fatalf("CreateJob = %+v, %v", j, err)
			}
			if err := s.SetThread(ctx, j.ID, "th", now); err != nil {
				t.Fatal(err)
			}
			if err := s.SetPR(ctx, j.ID, 4, now); err != nil {
				t.Fatal(err)
			}
			j.ThreadID, j.PR = "th", 4
			check := func() {
				t.Helper()
				lookups := map[string]func() (Job, error){
					"id":           func() (Job, error) { return s.JobByID(ctx, j.ID) },
					"issue":        func() (Job, error) { return s.JobByIssue(ctx, j.Issue) },
					"thread":       func() (Job, error) { return s.JobByThread(ctx, j.ThreadID) },
					"issue number": func() (Job, error) { return s.JobByNumber(ctx, j.Issue) },
					"PR number":    func() (Job, error) { return s.JobByNumber(ctx, j.PR) },
				}
				for name, lookup := range lookups {
					if got, err := lookup(); err != nil || !reflect.DeepEqual(got, j) {
						t.Errorf("%s = %+v, %v; want %+v", name, got, err, j)
					}
				}
				if got, err := s.OpenJobsWithPR(ctx); err != nil || !reflect.DeepEqual(got, []Job{j}) {
					t.Errorf("OpenJobsWithPR = %+v, %v", got, err)
				}
				if got, err := s.RunByID(ctx, r.ID); err != nil || got.JobID != j.ID {
					t.Errorf("attached run = %+v, %v", got, err)
				}
			}
			check()
			if err := s.Close(); err != nil {
				t.Fatal(err)
			}
			s, err = Open(path)
			if err != nil {
				t.Fatal(err)
			}
			check()
		})
	}
}

func TestJobHarnessConstraints(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	now := time.Unix(1_800_000_000, 0)
	if _, err := s.CreateJob(ctx, Job{Issue: 1, Harness: "invalid"}, 0, now); err == nil || !strings.Contains(err.Error(), "CHECK constraint failed") {
		t.Fatalf("invalid CreateJob harness: %v", err)
	}
	j, err := s.CreateJob(ctx, Job{Issue: 1}, 0, now)
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range []any{"invalid", "CODEX", nil} {
		if _, err := s.db.ExecContext(ctx, "UPDATE jobs SET harness = ? WHERE id = ?", value, j.ID); err == nil {
			t.Errorf("database accepted harness %v", value)
		}
	}
	if got, err := s.JobByID(ctx, j.ID); err != nil || got.Harness != "" {
		t.Fatalf("legacy harness = %+v, %v", got, err)
	}
	// Only pi jobs carry a model.
	if _, err := s.CreateJob(ctx, Job{Issue: 2, Harness: "codex", Model: "openai-codex/gpt-6.1-sol"}, 0, now); err == nil || !strings.Contains(err.Error(), "CHECK constraint failed") {
		t.Fatalf("model on a codex job: %v", err)
	}
	if _, err := s.CreateJob(ctx, Job{Issue: 2, Harness: "pi", Model: "openrouter/z-ai/glm-5.3"}, 0, now); err != nil {
		t.Fatalf("pi job: %v", err)
	}
}

func TestMigrateV4RebuildsJobsKeepingReferences(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "v4.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, migration := range migrations[:4] {
		if _, err := db.ExecContext(ctx, migration); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.ExecContext(ctx, `PRAGMA user_version = 4;
		INSERT INTO jobs (id, issue, pr, title, channel_id, thread_id, requester_id, requester_name, state, conflict_sha, resolve_sha, harness, created_at, updated_at)
		VALUES (7, 3, 4, 'codex job', 'c', 'th', 'u', 'U', 'open', 'conflict', 'resolve', 'codex', 1800000000, 1800000010);
		INSERT INTO runs (id, job_id, mode, instructions, user_id, status, created_at, updated_at)
		VALUES (9, 7, 'revise', 'keep this', 'u', 'completed', 1800000000, 1800000010);
		INSERT INTO merges (id, job_id, pr, approved_sha, head_sha, approver_id, approver_name, status, created_at, updated_at)
		VALUES (5, 7, 4, 'aaa', 'aaa', 'a', 'A', 'queued', 1800000000, 1800000000);`); err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	want := Job{ID: 7, Issue: 3, PR: 4, Title: "codex job", ChannelID: "c", ThreadID: "th", RequesterID: "u", RequesterName: "U", State: JobOpen, Harness: "codex", ConflictSHA: "conflict", ResolveSHA: "resolve", CreatedAt: time.Unix(1800000000, 0)}
	if got, err := s.JobByID(ctx, 7); err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("migrated job = %+v, %v; want %+v", got, err, want)
	}
	// Dropping the old table must not have cascaded to its runs or merges.
	if r, err := s.RunByID(ctx, 9); err != nil || r.JobID != 7 {
		t.Fatalf("run after rebuild = %+v, %v", r, err)
	}
	if m, err := s.ActiveMergeForJob(ctx, 7); err != nil || m.ID != 5 {
		t.Fatalf("merge after rebuild = %+v, %v", m, err)
	}
	// Foreign keys and the PR index are back in force.
	if _, err := s.db.ExecContext(ctx, `INSERT INTO runs (job_id, mode, user_id, status, created_at, updated_at) VALUES (999, 'implement', 'u', 'reserved', 0, 0)`); err == nil {
		t.Fatal("run for a missing job accepted")
	}
	if _, err := s.CreateJob(ctx, Job{Issue: 8}, 0, time.Unix(1800000000, 0)); err != nil {
		t.Fatal(err)
	}
	if _, err := s.db.ExecContext(ctx, `UPDATE jobs SET pr = 4 WHERE issue = 8`); err == nil {
		t.Fatal("duplicate PR accepted")
	}
	if _, err := s.db.ExecContext(ctx, `UPDATE jobs SET harness = 'pi' WHERE id = 7`); err != nil {
		t.Fatalf("pi harness after migration: %v", err)
	}
}

func TestMigrateV3JobHarness(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "v3.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, migration := range migrations[:3] {
		if _, err := db.ExecContext(ctx, migration); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.ExecContext(ctx, `PRAGMA user_version = 3;
		INSERT INTO jobs (id, issue, pr, title, channel_id, thread_id, requester_id, requester_name, state, conflict_sha, resolve_sha, created_at, updated_at)
		VALUES (7, 3, 4, 'legacy', 'c', 'th', 'u', 'U', 'open', 'conflict', 'resolve', 1800000000, 1800000010);
		INSERT INTO runs (id, job_id, mode, instructions, user_id, status, conclusion, workflow_run_id, run_url, relayed, created_at, updated_at)
		VALUES (9, 7, 'revise', 'keep this', 'u', 'completed', 'success', 11, 'url', 2, 1800000000, 1800000010);`); err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	var version int
	if err := s.db.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil || version != len(migrations) {
		t.Fatalf("version = %d, %v", version, err)
	}
	wantJob := Job{ID: 7, Issue: 3, PR: 4, Title: "legacy", ChannelID: "c", ThreadID: "th", RequesterID: "u", RequesterName: "U", State: JobOpen, ConflictSHA: "conflict", ResolveSHA: "resolve", CreatedAt: time.Unix(1800000000, 0)}
	if got, err := s.JobByID(ctx, 7); err != nil || !reflect.DeepEqual(got, wantJob) {
		t.Fatalf("migrated job = %+v, %v; want %+v", got, err, wantJob)
	}
	wantRun := Run{ID: 9, JobID: 7, Mode: "revise", Instructions: "keep this", UserID: "u", Status: RunCompleted, Conclusion: "success", WorkflowRunID: 11, RunURL: "url", Relayed: 2, CreatedAt: time.Unix(1800000000, 0), UpdatedAt: time.Unix(1800000010, 0)}
	if got, err := s.RunByID(ctx, 9); err != nil || !reflect.DeepEqual(got, wantRun) {
		t.Fatalf("migrated run = %+v, %v; want %+v", got, err, wantRun)
	}
}

func TestSeen(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	now := time.Unix(1_800_000_000, 0)
	if fresh, _ := s.MarkSeen(ctx, "k", now); !fresh {
		t.Error("first mark not fresh")
	}
	if fresh, _ := s.MarkSeen(ctx, "k", now); fresh {
		t.Error("second mark fresh")
	}
	s.Purge(ctx, now.Add(48*time.Hour), 24*time.Hour)
	if fresh, _ := s.MarkSeen(ctx, "k", now); !fresh {
		t.Error("purged key still seen")
	}
}

func TestMergeQueue(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	now := time.Unix(1_800_000_000, 0)
	r, _ := s.Reserve(ctx, "1", 0, "implement", "", Limits{Window: time.Hour}, now)
	j, err := s.CreateJob(ctx, Job{Issue: 3, Title: "t", ChannelID: "c", RequesterID: "1", RequesterName: "A"}, r.ID, now)
	if err != nil {
		t.Fatal(err)
	}
	m, err := s.Enqueue(ctx, Merge{JobID: j.ID, PR: 4, ApprovedSHA: "aaa", ApproverID: "2", ApproverName: "B"}, now)
	if err != nil || m.HeadSHA != "aaa" || m.Status != MergeQueued {
		t.Fatalf("enqueue %+v %v", m, err)
	}
	if _, err := s.Enqueue(ctx, Merge{JobID: j.ID, PR: 4, ApprovedSHA: "bbb"}, now); !errors.Is(err, ErrQueued) {
		t.Errorf("second approval: %v", err)
	}
	s.UpdateMerge(ctx, m.ID, MergeTesting, "ccc", "", now)
	got, err := s.ActiveMergeForJob(ctx, j.ID)
	if err != nil || got.HeadSHA != "ccc" || got.ApprovedSHA != "aaa" || got.Status != MergeTesting {
		t.Errorf("active %+v %v", got, err)
	}
	s.SetMerged(ctx, m.ID, "ddd", now)
	if q, _ := s.MergeQueue(ctx); len(q) != 0 {
		t.Errorf("queue %+v", q)
	}
	// Once merged, the PR may be approved again (a reopened PR, say).
	if _, err := s.Enqueue(ctx, Merge{JobID: j.ID, PR: 4, ApprovedSHA: "eee"}, now); err != nil {
		t.Errorf("new approval: %v", err)
	}
	if v, _ := s.Get(ctx, "k"); v != "" {
		t.Errorf("unset key %q", v)
	}
	s.Set(ctx, "k", "1")
	s.Set(ctx, "k", "2")
	if v, _ := s.Get(ctx, "k"); v != "2" {
		t.Errorf("key %q", v)
	}
}
