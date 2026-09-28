package store

import (
	"context"
	"errors"
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
