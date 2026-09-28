// Package store persists the bot's jobs (one per Discord feature request), their agent
// runs, and the GitHub deliveries and comments it has already handled, in SQLite.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite" // pure-Go SQLite driver, registered as "sqlite"
)

var ErrNotFound = errors.New("not found")

// Run statuses. A run is active from the moment a user asks for it until its workflow
// run completes, so reservations count against the limits before GitHub is called.
const (
	RunReserved   = "reserved"    // limits checked, not dispatched yet
	RunDispatched = "dispatched"  // workflow_dispatch accepted, no workflow run seen yet
	RunQueued     = "queued"      // workflow run seen, waiting for a runner
	RunInProgress = "in_progress" // workflow run started
	RunCompleted  = "completed"   // workflow run finished (see Conclusion)
	RunFailed     = "failed"      // never started: the issue or dispatch failed, or it was lost
)

// ActiveStatuses are the statuses that count toward the concurrency cap.
var ActiveStatuses = []string{RunReserved, RunDispatched, RunQueued, RunInProgress}

// Job states.
const (
	JobOpen   = "open"
	JobMerged = "merged"
	JobClosed = "closed"
)

// Job is one feature request: a Discord thread, a GitHub issue and (later) its PR.
type Job struct {
	ID            int64
	Issue         int
	PR            int
	Title         string
	ChannelID     string
	ThreadID      string
	RequesterID   string
	RequesterName string
	State         string
	ConflictSHA   string // head SHA last found to conflict with the base branch
	ResolveSHA    string // head SHA a resolve-conflicts run was started for
	CreatedAt     time.Time
}

// Run is one agent run requested from Discord.
type Run struct {
	ID            int64
	JobID         int64 // 0 while a feature's issue doesn't exist yet
	Mode          string
	UserID        string
	Status        string
	Conclusion    string
	WorkflowRunID int64
	RunURL        string
	Relayed       int // comments relayed to the thread while this run was active
	CreatedAt     time.Time
	UpdatedAt     time.Time
}

type Store struct {
	db *sql.DB
}

// Open opens (creating if needed) the database at path and applies migrations.
// Use ":memory:" for tests.
func Open(path string) (*Store, error) {
	dsn := "file:" + path + "?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_txlock=immediate"
	if path != ":memory:" {
		dsn += "&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)"
	}
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	// One connection serializes writes (no SQLITE_BUSY) and keeps ":memory:" a single DB.
	db.SetMaxOpenConns(1)
	s := &Store{db: db}
	if err := s.migrate(context.Background()); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

// Ping checks that the database answers.
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

// migrations are applied in order; PRAGMA user_version records how many ran.
// Never edit an applied migration: append a new one.
var migrations = []string{
	`CREATE TABLE jobs (
		id             INTEGER PRIMARY KEY,
		issue          INTEGER NOT NULL UNIQUE,
		pr             INTEGER,
		title          TEXT NOT NULL,
		channel_id     TEXT NOT NULL,
		thread_id      TEXT UNIQUE,
		requester_id   TEXT NOT NULL,
		requester_name TEXT NOT NULL,
		state          TEXT NOT NULL DEFAULT 'open',
		created_at     INTEGER NOT NULL,
		updated_at     INTEGER NOT NULL
	);
	CREATE UNIQUE INDEX jobs_pr ON jobs(pr) WHERE pr IS NOT NULL;
	CREATE TABLE runs (
		id              INTEGER PRIMARY KEY,
		job_id          INTEGER REFERENCES jobs(id) ON DELETE CASCADE,
		mode            TEXT NOT NULL,
		user_id         TEXT NOT NULL,
		status          TEXT NOT NULL,
		conclusion      TEXT NOT NULL DEFAULT '',
		workflow_run_id INTEGER,
		run_url         TEXT NOT NULL DEFAULT '',
		relayed         INTEGER NOT NULL DEFAULT 0,
		created_at      INTEGER NOT NULL,
		updated_at      INTEGER NOT NULL
	);
	CREATE INDEX runs_user ON runs(user_id, created_at);
	CREATE INDEX runs_status ON runs(status);
	CREATE INDEX runs_job ON runs(job_id);
	CREATE TABLE seen (
		key TEXT PRIMARY KEY,
		at  INTEGER NOT NULL
	);`,
	// 2: Discord approvals and the merge queue, conflict tracking, and small settings.
	`CREATE TABLE merges (
		id            INTEGER PRIMARY KEY,
		job_id        INTEGER NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
		pr            INTEGER NOT NULL,
		approved_sha  TEXT NOT NULL,
		head_sha      TEXT NOT NULL,
		approver_id   TEXT NOT NULL,
		approver_name TEXT NOT NULL,
		status        TEXT NOT NULL,
		detail        TEXT NOT NULL DEFAULT '',
		merged_sha    TEXT NOT NULL DEFAULT '',
		announced     INTEGER NOT NULL DEFAULT 0,
		created_at    INTEGER NOT NULL,
		updated_at    INTEGER NOT NULL
	);
	CREATE UNIQUE INDEX merges_active ON merges(pr) WHERE status IN ('queued', 'updating', 'testing');
	CREATE INDEX merges_status ON merges(status);
	ALTER TABLE jobs ADD COLUMN conflict_sha TEXT NOT NULL DEFAULT '';
	ALTER TABLE jobs ADD COLUMN resolve_sha TEXT NOT NULL DEFAULT '';
	CREATE TABLE kv (
		key   TEXT PRIMARY KEY,
		value TEXT NOT NULL
	);`,
}

func (s *Store) migrate(ctx context.Context) error {
	var version int
	if err := s.db.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	for i := version; i < len(migrations); i++ {
		tx, err := s.db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, migrations[i]); err != nil {
			tx.Rollback()
			return fmt.Errorf("migration %d: %w", i+1, err)
		}
		if _, err := tx.ExecContext(ctx, fmt.Sprintf("PRAGMA user_version = %d", i+1)); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

// --- limits and reservations ------------------------------------------------------------

// Limits caps how many runs one user may start per window and how many may be active.
type Limits struct {
	PerUser    int
	Window     time.Duration
	MaxActive  int
	StaleAfter time.Duration // active runs older than this no longer count
}

// LimitError says which limit refused a reservation.
type LimitError struct {
	Active bool // true: the concurrency cap; false: the per-user limit
	Limit  int
	Retry  time.Time // per-user: when the oldest counted run leaves the window
}

func (e *LimitError) Error() string {
	if e.Active {
		return fmt.Sprintf("%d agent runs are already active", e.Limit)
	}
	return fmt.Sprintf("per-user limit of %d runs reached", e.Limit)
}

// Reserve atomically checks the limits and records a reserved run for userID.
// jobID may be 0 for a feature whose issue doesn't exist yet.
func (s *Store) Reserve(ctx context.Context, userID string, jobID int64, mode string, lim Limits, now time.Time) (Run, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Run{}, err
	}
	defer tx.Rollback()

	var used int
	var oldest sql.NullInt64
	err = tx.QueryRowContext(ctx,
		`SELECT COUNT(*), MIN(created_at) FROM runs WHERE user_id = ? AND created_at > ? AND status != ?`,
		userID, now.Add(-lim.Window).Unix(), RunFailed).Scan(&used, &oldest)
	if err != nil {
		return Run{}, err
	}
	if lim.PerUser > 0 && used >= lim.PerUser {
		return Run{}, &LimitError{Limit: lim.PerUser, Retry: time.Unix(oldest.Int64, 0).Add(lim.Window)}
	}
	var active int
	err = tx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM runs WHERE status IN (`+placeholders(len(ActiveStatuses))+`) AND updated_at > ?`,
		append(anys(ActiveStatuses), now.Add(-lim.StaleAfter).Unix())...).Scan(&active)
	if err != nil {
		return Run{}, err
	}
	if lim.MaxActive > 0 && active >= lim.MaxActive {
		return Run{}, &LimitError{Active: true, Limit: lim.MaxActive}
	}
	res, err := tx.ExecContext(ctx,
		`INSERT INTO runs (job_id, mode, user_id, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)`,
		nullableID(jobID), mode, userID, RunReserved, now.Unix(), now.Unix())
	if err != nil {
		return Run{}, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Run{}, err
	}
	if err := tx.Commit(); err != nil {
		return Run{}, err
	}
	return Run{ID: id, JobID: jobID, Mode: mode, UserID: userID, Status: RunReserved, CreatedAt: now, UpdatedAt: now}, nil
}

// --- jobs ----------------------------------------------------------------------------------

// CreateJob records the job for a new issue and attaches the reserved run to it.
func (s *Store) CreateJob(ctx context.Context, j Job, runID int64, now time.Time) (Job, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Job{}, err
	}
	defer tx.Rollback()
	res, err := tx.ExecContext(ctx,
		`INSERT INTO jobs (issue, title, channel_id, requester_id, requester_name, state, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		j.Issue, j.Title, j.ChannelID, j.RequesterID, j.RequesterName, JobOpen, now.Unix(), now.Unix())
	if err != nil {
		return Job{}, err
	}
	if j.ID, err = res.LastInsertId(); err != nil {
		return Job{}, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE runs SET job_id = ? WHERE id = ?`, j.ID, runID); err != nil {
		return Job{}, err
	}
	j.State, j.CreatedAt = JobOpen, now
	return j, tx.Commit()
}

const jobCols = `id, issue, COALESCE(pr, 0), title, channel_id, COALESCE(thread_id, ''), requester_id,
	requester_name, state, conflict_sha, resolve_sha, created_at`

func scanJob(row interface{ Scan(...any) error }) (Job, error) {
	var j Job
	var created int64
	err := row.Scan(&j.ID, &j.Issue, &j.PR, &j.Title, &j.ChannelID, &j.ThreadID, &j.RequesterID,
		&j.RequesterName, &j.State, &j.ConflictSHA, &j.ResolveSHA, &created)
	if errors.Is(err, sql.ErrNoRows) {
		return Job{}, ErrNotFound
	}
	j.CreatedAt = time.Unix(created, 0)
	return j, err
}

func (s *Store) JobByID(ctx context.Context, id int64) (Job, error) {
	return scanJob(s.db.QueryRowContext(ctx, "SELECT "+jobCols+" FROM jobs WHERE id = ?", id))
}

func (s *Store) JobByThread(ctx context.Context, threadID string) (Job, error) {
	return scanJob(s.db.QueryRowContext(ctx, "SELECT "+jobCols+" FROM jobs WHERE thread_id = ?", threadID))
}

func (s *Store) JobByIssue(ctx context.Context, issue int) (Job, error) {
	return scanJob(s.db.QueryRowContext(ctx, "SELECT "+jobCols+" FROM jobs WHERE issue = ?", issue))
}

// JobByNumber finds the job whose issue or PR has this number (they share a sequence).
func (s *Store) JobByNumber(ctx context.Context, n int) (Job, error) {
	return scanJob(s.db.QueryRowContext(ctx, "SELECT "+jobCols+" FROM jobs WHERE issue = ? OR pr = ?", n, n))
}

func (s *Store) SetThread(ctx context.Context, jobID int64, threadID string, now time.Time) error {
	return s.exec(ctx, `UPDATE jobs SET thread_id = ?, updated_at = ? WHERE id = ?`, threadID, now.Unix(), jobID)
}

func (s *Store) SetPR(ctx context.Context, jobID int64, pr int, now time.Time) error {
	return s.exec(ctx, `UPDATE jobs SET pr = ?, updated_at = ? WHERE id = ?`, pr, now.Unix(), jobID)
}

func (s *Store) SetJobState(ctx context.Context, jobID int64, state string, now time.Time) error {
	return s.exec(ctx, `UPDATE jobs SET state = ?, updated_at = ? WHERE id = ?`, state, now.Unix(), jobID)
}

// SetConflict records the head SHA found to conflict with the base branch ("" clears it).
func (s *Store) SetConflict(ctx context.Context, jobID int64, sha string, now time.Time) error {
	return s.exec(ctx, `UPDATE jobs SET conflict_sha = ?, updated_at = ? WHERE id = ?`, sha, now.Unix(), jobID)
}

// SetResolve records the head SHA a resolve-conflicts run was started for.
func (s *Store) SetResolve(ctx context.Context, jobID int64, sha string, now time.Time) error {
	return s.exec(ctx, `UPDATE jobs SET resolve_sha = ?, updated_at = ? WHERE id = ?`, sha, now.Unix(), jobID)
}

// OpenJobsWithPR lists open jobs whose PR is known, oldest first.
func (s *Store) OpenJobsWithPR(ctx context.Context) ([]Job, error) {
	rows, err := s.db.QueryContext(ctx,
		"SELECT "+jobCols+" FROM jobs WHERE state = ? AND pr IS NOT NULL ORDER BY id", JobOpen)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Job
	for rows.Next() {
		j, err := scanJob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

// --- runs ----------------------------------------------------------------------------------

const runCols = `id, COALESCE(job_id, 0), mode, user_id, status, conclusion, COALESCE(workflow_run_id, 0),
	run_url, relayed, created_at, updated_at`

func scanRun(row interface{ Scan(...any) error }) (Run, error) {
	var r Run
	var created, updated int64
	err := row.Scan(&r.ID, &r.JobID, &r.Mode, &r.UserID, &r.Status, &r.Conclusion, &r.WorkflowRunID,
		&r.RunURL, &r.Relayed, &created, &updated)
	if errors.Is(err, sql.ErrNoRows) {
		return Run{}, ErrNotFound
	}
	r.CreatedAt, r.UpdatedAt = time.Unix(created, 0), time.Unix(updated, 0)
	return r, err
}

func (s *Store) RunByID(ctx context.Context, id int64) (Run, error) {
	return scanRun(s.db.QueryRowContext(ctx, "SELECT "+runCols+" FROM runs WHERE id = ?", id))
}

// ActiveRunForJob returns the newest active run of a job, or ErrNotFound.
func (s *Store) ActiveRunForJob(ctx context.Context, jobID int64) (Run, error) {
	return scanRun(s.db.QueryRowContext(ctx,
		"SELECT "+runCols+" FROM runs WHERE job_id = ? AND status IN ("+placeholders(len(ActiveStatuses))+
			") ORDER BY id DESC LIMIT 1",
		append([]any{jobID}, anys(ActiveStatuses)...)...))
}

// ActiveRuns lists every active run, oldest first.
func (s *Store) ActiveRuns(ctx context.Context) ([]Run, error) {
	rows, err := s.db.QueryContext(ctx,
		"SELECT "+runCols+" FROM runs WHERE status IN ("+placeholders(len(ActiveStatuses))+") ORDER BY id",
		anys(ActiveStatuses)...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Run
	for rows.Next() {
		r, err := scanRun(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// SetRunStatus moves a run to status, keeping the workflow run details once known.
func (s *Store) SetRunStatus(ctx context.Context, id int64, status, conclusion string, workflowRunID int64, url string, now time.Time) error {
	return s.exec(ctx, `UPDATE runs SET status = ?, conclusion = ?,
		workflow_run_id = COALESCE(NULLIF(?, 0), workflow_run_id), run_url = COALESCE(NULLIF(?, ''), run_url),
		updated_at = ? WHERE id = ?`, status, conclusion, workflowRunID, url, now.Unix(), id)
}

// CountRelayed notes that a comment was relayed while this run was active.
func (s *Store) CountRelayed(ctx context.Context, id int64) error {
	return s.exec(ctx, `UPDATE runs SET relayed = relayed + 1 WHERE id = ?`, id)
}

// --- merges -------------------------------------------------------------------------------

// Merge queue statuses. An approval enters the queue as queued; the coordinator takes the
// oldest active one and moves it through updating (the branch is being brought up to date
// with the base) and testing (waiting for CI on the new head) to merged, or drops it.
const (
	MergeQueued   = "queued"
	MergeUpdating = "updating"
	MergeTesting  = "testing"
	MergeMerged   = "merged"
	MergeDropped  = "dropped" // see Detail
)

// ActiveMergeStatuses are the statuses of approvals still in the queue.
var ActiveMergeStatuses = []string{MergeQueued, MergeUpdating, MergeTesting}

// Merge is one Discord approval of a PR at a head SHA, and its way through the queue.
type Merge struct {
	ID           int64
	JobID        int64
	PR           int
	ApprovedSHA  string // the head SHA the approver saw
	HeadSHA      string // the current head: ApprovedSHA plus any updates from the base
	ApproverID   string
	ApproverName string
	Status       string
	Detail       string
	MergedSHA    string
	Announced    bool // the deploy that contains MergedSHA was announced
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// ErrQueued means the PR already has an approval in the queue.
var ErrQueued = errors.New("already queued")

// Enqueue adds an approval to the merge queue.
func (s *Store) Enqueue(ctx context.Context, m Merge, now time.Time) (Merge, error) {
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO merges (job_id, pr, approved_sha, head_sha, approver_id, approver_name, status, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		m.JobID, m.PR, m.ApprovedSHA, m.ApprovedSHA, m.ApproverID, m.ApproverName, MergeQueued, now.Unix(), now.Unix())
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return Merge{}, ErrQueued
		}
		return Merge{}, err
	}
	if m.ID, err = res.LastInsertId(); err != nil {
		return Merge{}, err
	}
	m.HeadSHA, m.Status, m.CreatedAt, m.UpdatedAt = m.ApprovedSHA, MergeQueued, now, now
	return m, nil
}

const mergeCols = `id, job_id, pr, approved_sha, head_sha, approver_id, approver_name, status, detail,
	merged_sha, announced, created_at, updated_at`

func scanMerge(row interface{ Scan(...any) error }) (Merge, error) {
	var m Merge
	var created, updated int64
	err := row.Scan(&m.ID, &m.JobID, &m.PR, &m.ApprovedSHA, &m.HeadSHA, &m.ApproverID, &m.ApproverName,
		&m.Status, &m.Detail, &m.MergedSHA, &m.Announced, &created, &updated)
	if errors.Is(err, sql.ErrNoRows) {
		return Merge{}, ErrNotFound
	}
	m.CreatedAt, m.UpdatedAt = time.Unix(created, 0), time.Unix(updated, 0)
	return m, err
}

func (s *Store) merges(ctx context.Context, where string, args ...any) ([]Merge, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT "+mergeCols+" FROM merges WHERE "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Merge
	for rows.Next() {
		m, err := scanMerge(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// MergeQueue lists the approvals still in the queue, in merge order (oldest first).
func (s *Store) MergeQueue(ctx context.Context) ([]Merge, error) {
	return s.merges(ctx, "status IN ("+placeholders(len(ActiveMergeStatuses))+") ORDER BY id",
		anys(ActiveMergeStatuses)...)
}

// ActiveMergeForJob returns the job's approval still in the queue, or ErrNotFound.
func (s *Store) ActiveMergeForJob(ctx context.Context, jobID int64) (Merge, error) {
	return scanMerge(s.db.QueryRowContext(ctx,
		"SELECT "+mergeCols+" FROM merges WHERE job_id = ? AND status IN ("+
			placeholders(len(ActiveMergeStatuses))+") ORDER BY id DESC LIMIT 1",
		append([]any{jobID}, anys(ActiveMergeStatuses)...)...))
}

// UnannouncedMerges lists merged approvals whose deploy hasn't been announced, oldest first.
func (s *Store) UnannouncedMerges(ctx context.Context) ([]Merge, error) {
	return s.merges(ctx, "status = ? AND announced = 0 ORDER BY id", MergeMerged)
}

// UpdateMerge moves an approval to status, with the current head and a detail message.
func (s *Store) UpdateMerge(ctx context.Context, id int64, status, headSHA, detail string, now time.Time) error {
	return s.exec(ctx, `UPDATE merges SET status = ?, head_sha = COALESCE(NULLIF(?, ''), head_sha), detail = ?,
		updated_at = ? WHERE id = ?`, status, headSHA, detail, now.Unix(), id)
}

// SetMerged records that the approval was merged as sha.
func (s *Store) SetMerged(ctx context.Context, id int64, sha string, now time.Time) error {
	return s.exec(ctx, `UPDATE merges SET status = ?, merged_sha = ?, detail = '', updated_at = ? WHERE id = ?`,
		MergeMerged, sha, now.Unix(), id)
}

// SetAnnounced records that the deploy containing the merge was announced.
func (s *Store) SetAnnounced(ctx context.Context, id int64) error {
	return s.exec(ctx, `UPDATE merges SET announced = 1 WHERE id = ?`, id)
}

// --- kv ------------------------------------------------------------------------------------

// Get returns a small setting, or "" if unset.
func (s *Store) Get(ctx context.Context, key string) (string, error) {
	var v string
	err := s.db.QueryRowContext(ctx, `SELECT value FROM kv WHERE key = ?`, key).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return v, err
}

// Set stores a small setting.
func (s *Store) Set(ctx context.Context, key, value string) error {
	return s.exec(ctx, `INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
		key, value)
}

// --- seen ----------------------------------------------------------------------------------

// MarkSeen records key and reports whether it was new. Keys name webhook deliveries,
// relayed comments and announced CI results, so each is handled once.
func (s *Store) MarkSeen(ctx context.Context, key string, now time.Time) (bool, error) {
	res, err := s.db.ExecContext(ctx, `INSERT OR IGNORE INTO seen (key, at) VALUES (?, ?)`, key, now.Unix())
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	return n == 1, err
}

// Purge forgets seen keys older than keep.
func (s *Store) Purge(ctx context.Context, now time.Time, keep time.Duration) error {
	return s.exec(ctx, `DELETE FROM seen WHERE at < ?`, now.Add(-keep).Unix())
}

// --- helpers -------------------------------------------------------------------------------

func (s *Store) exec(ctx context.Context, q string, args ...any) error {
	_, err := s.db.ExecContext(ctx, q, args...)
	return err
}

func placeholders(n int) string { return strings.TrimSuffix(strings.Repeat("?, ", n), ", ") }

func anys(ss []string) []any {
	out := make([]any, len(ss))
	for i, s := range ss {
		out[i] = s
	}
	return out
}

func nullableID(id int64) any {
	if id == 0 {
		return nil
	}
	return id
}
