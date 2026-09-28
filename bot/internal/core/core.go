// Package core is the bot's logic, independent of Discord and HTTP: it turns /feature and
// /revise into GitHub issues and agent.yml dispatches, and GitHub events into thread
// updates. The Discord adapter and the webhook handler call into it.
package core

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/tfpp/the-game/bot/internal/github"
	"github.com/tfpp/the-game/bot/internal/store"
)

// GitHub is what the bot needs from the GitHub App client.
type GitHub interface {
	CreateIssue(ctx context.Context, title, body string) (github.Issue, error)
	Dispatch(ctx context.Context, workflow, ref string, inputs map[string]string) error
	WorkflowRuns(ctx context.Context, workflow string, since time.Time) ([]github.WorkflowRun, error)
	Comments(ctx context.Context, n int, since time.Time) ([]github.Comment, error)

	// Closing (/close).
	CreateComment(ctx context.Context, n int, body string) error
	CloseIssue(ctx context.Context, n int) error
	ClosePullRequest(ctx context.Context, n int) error

	// Merging.
	PullRequest(ctx context.Context, n int) (github.PullRequest, error)
	PullRequestFiles(ctx context.Context, n int) ([]string, error)
	FileContent(ctx context.Context, path, ref string) ([]byte, error)
	Compare(ctx context.Context, base, head string) (github.Comparison, error)
	CommitParents(ctx context.Context, sha string) ([]string, error)
	WorkflowRunsForSHA(ctx context.Context, workflow, sha string) ([]github.WorkflowRun, error)
	UpdateBranch(ctx context.Context, n int, expectedHead string) error
	SquashMerge(ctx context.Context, n int, sha, title, message string) (string, error)
	DeleteBranch(ctx context.Context, branch string) error

	// Release announcements (release.go).
	Releases(ctx context.Context) ([]github.Release, error)
}

// Chat posts to Discord threads. content may mention only the users in ping.
type Chat interface {
	Post(ctx context.Context, threadID, content string, ping ...string) error
	// PostButton posts content with one button; pressing it reaches the Discord adapter
	// with id as its custom ID. It pings nobody.
	PostButton(ctx context.Context, threadID, content, label, id string) error
}

// Deployer asks the host to deploy game server and accounts API builds. Nil turns
// deploys off.
type Deployer interface {
	// Deploy requests a deploy of the server image built from commit sha.
	Deploy(ctx context.Context, sha string) error
	// DeployAPI requests a deploy of the accounts API image built from commit sha.
	DeployAPI(ctx context.Context, sha string) error
	// Deployed returns the commit of the last successful deploy, or "".
	Deployed(ctx context.Context) (string, error)
}

// Responder answers one slash command.
type Responder interface {
	// Reject answers privately. Only valid before Defer.
	Reject(ctx context.Context, msg string) error
	// Defer acknowledges the command publicly; the answer follows with Respond.
	Defer(ctx context.Context) error
	// Respond sets the public answer.
	Respond(ctx context.Context, content string) error
	// Thread opens a public thread on the answer and returns its ID.
	Thread(ctx context.Context, name string) (string, error)
}

// Config holds the bot's settings.
type Config struct {
	Repo       string // owner/name
	Ref        string // branch agent.yml is dispatched on (main)
	Workflow   string // agent workflow file (agent.yml)
	CIWorkflow string // CI workflow file (game-ci.yml)
	Agent      string // agent input (claude)
	// Workflows whose successful runs on Ref mean a build is ready to deploy: the server
	// is deployed once both have finished for the same commit.
	ServerWorkflow string // server-image.yml
	PagesWorkflow  string // pages.yml
	// A successful run of APIWorkflow on Ref deploys the accounts API built from it.
	APIWorkflow string // api-image.yml
	// PR previews: successful "preview #N deploy" runs of PreviewWorkflow on agent
	// branches post PreviewURL, with {pr} replaced by N, to the thread. Empty turns it off.
	PreviewWorkflow string // preview.yml
	PreviewURL      string // https://pr-{pr}.tfpp-game.pages.dev/
	// Discord channel for release announcements (release.go). Empty turns them off.
	ReleaseChannelID string
	Limits           store.Limits
	Deployer         Deployer
	Logger           *slog.Logger
	Now              func() time.Time
}

// Service implements the bot's commands and event handling.
type Service struct {
	cfg   Config
	st    *store.Store
	gh    GitHub
	chat  Chat
	log   *slog.Logger
	mu    sync.Mutex // serializes limit checks with reservations
	prURL *regexp.Regexp

	mergeMu sync.Mutex    // one coordinator step at a time
	kick    chan struct{} // wakes the coordinator
}

func New(cfg Config, st *store.Store, gh GitHub, chat Chat) *Service {
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	return &Service{
		cfg: cfg, st: st, gh: gh, chat: chat, log: cfg.Logger, kick: make(chan struct{}, 1),
		prURL: regexp.MustCompile(`^🤖 Opened https://github\.com/` + regexp.QuoteMeta(cfg.Repo) + `/pull/(\d+)`),
	}
}

const (
	minRequest = 10
	maxRequest = 1500
	// A reserved run that was never dispatched (the bot crashed midway) is dropped after
	// this; a dispatched run that never shows up as a workflow run, likewise.
	reservedTimeout   = 10 * time.Minute
	dispatchedTimeout = 15 * time.Minute
)

// --- commands ------------------------------------------------------------------------------

// FeatureRequest is a /feature command.
type FeatureRequest struct {
	UserID    string
	UserName  string
	HasRole   bool
	ChannelID string
	Text      string
}

// Feature handles /feature: checks, issue, thread, dispatch.
func (s *Service) Feature(ctx context.Context, req FeatureRequest, r Responder) error {
	text := strings.TrimSpace(strings.ReplaceAll(req.Text, "\r", ""))
	if !req.HasRole {
		return r.Reject(ctx, "You need the requester role to ask for features.")
	}
	if n := utf8.RuneCountInString(text); n < minRequest || n > maxRequest {
		return r.Reject(ctx, fmt.Sprintf("Describe the feature in %d to %d characters.", minRequest, maxRequest))
	}
	run, err := s.reserve(ctx, req.UserID, 0, "implement", "")
	if err != nil {
		return s.rejectLimit(ctx, r, err)
	}
	if err := r.Defer(ctx); err != nil {
		s.failRun(ctx, run.ID)
		return err
	}

	name := cleanName(req.UserName)
	title := issueTitle(text)
	body := neutralizeMentions(text) + "\n\nRequested-by: " + name + " <discord:" + req.UserID + ">\n"
	issue, err := s.gh.CreateIssue(ctx, title, body)
	if err != nil {
		s.failRun(ctx, run.ID)
		s.log.Error("create issue", "err", err)
		return r.Respond(ctx, "❌ I couldn't open a GitHub issue for this. Try again later.")
	}
	job, err := s.st.CreateJob(ctx, store.Job{
		Issue: issue.Number, Title: title, ChannelID: req.ChannelID,
		RequesterID: req.UserID, RequesterName: name,
	}, run.ID, s.cfg.Now())
	if err != nil {
		s.failRun(ctx, run.ID)
		return fmt.Errorf("create job: %w", err)
	}
	run.JobID = job.ID

	announce := fmt.Sprintf("**%s**\nRequested by <@%s> · [issue #%d](<%s>)\n%s",
		escape(title), req.UserID, issue.Number, issue.HTMLURL, quote(text, 300))
	if err := r.Respond(ctx, announce); err != nil {
		s.log.Error("respond to /feature", "err", err, "issue", issue.Number)
	}
	threadID, err := r.Thread(ctx, threadName(issue.Number, title))
	if err != nil {
		s.log.Error("open thread", "err", err, "issue", issue.Number)
	} else if err := s.st.SetThread(ctx, job.ID, threadID, s.cfg.Now()); err != nil {
		return err
	}
	job.ThreadID = threadID

	if run.Status == store.RunWaiting {
		s.post(ctx, job, fmt.Sprintf("<@%s> The agent is busy, so this is %s. I'll start it when a slot "+
			"frees up and post progress here. Once the PR is open, use `/revise` in this thread to ask for changes.",
			req.UserID, s.linePosition(ctx, run.ID)), req.UserID)
		s.drain(ctx) // a slot may have freed up meanwhile
		return nil
	}
	if err := s.dispatch(ctx, run, issue.Number, ""); err != nil {
		s.post(ctx, job, "❌ I couldn't start the agent. Try `/feature` again later.")
		return nil
	}
	s.post(ctx, job, fmt.Sprintf("<@%s> The agent is queued; I'll post progress here. "+
		"Once the PR is open, use `/revise` in this thread to ask for changes.", req.UserID), req.UserID)
	return nil
}

// linePosition describes a waiting run's place in line.
func (s *Service) linePosition(ctx context.Context, runID int64) string {
	n, err := s.st.WaitingPosition(ctx, runID)
	switch {
	case err != nil || n < 1:
		return "waiting in line"
	case n == 1:
		return "next in line"
	}
	return fmt.Sprintf("number %d in line", n)
}

// drain dispatches waiting runs while agent slots are free. Errors are logged: the next
// call retries.
func (s *Service) drain(ctx context.Context) {
	for {
		s.mu.Lock()
		run, err := s.st.StartWaiting(ctx, s.cfg.Limits, s.cfg.Now())
		s.mu.Unlock()
		if errors.Is(err, store.ErrNotFound) {
			return
		} else if err != nil {
			s.log.Error("start waiting run", "err", err)
			return
		}
		s.startWaiting(ctx, run)
	}
}

// startWaiting dispatches a run that waited for a slot, or drops it if its job moved on.
func (s *Service) startWaiting(ctx context.Context, run store.Run) {
	job, err := s.st.JobByID(ctx, run.JobID)
	if err != nil {
		s.log.Error("job of waiting run", "err", err, "run", run.ID)
		s.failRun(ctx, run.ID)
		return
	}
	number := job.PR
	switch {
	case job.State != store.JobOpen:
		s.failRun(ctx, run.ID)
		return
	case run.Mode == "implement":
		number = job.Issue
	case run.Mode == "resolve-conflicts" && (job.ConflictSHA == "" || job.ConflictSHA != job.ResolveSHA):
		s.failRun(ctx, run.ID) // the head moved on; the next conflict check decides again
		return
	}
	if err := s.dispatch(ctx, run, number, run.Instructions); err != nil {
		if run.Mode == "resolve-conflicts" {
			if err := s.st.SetResolve(ctx, job.ID, "", s.cfg.Now()); err != nil { // retry later
				s.log.Error("reset resolve", "err", err, "job", job.ID)
			}
			return
		}
		s.post(ctx, job, fmt.Sprintf("❌ <@%s> I couldn't start the agent. Try again later.", run.UserID), run.UserID)
		return
	}
	switch run.Mode {
	case "implement":
		s.post(ctx, job, fmt.Sprintf("<@%s> A slot freed up: the agent is queued; I'll post progress here.",
			job.RequesterID), job.RequesterID)
	case "resolve-conflicts":
		s.post(ctx, job, fmt.Sprintf("🔧 The agent is merging %s into PR #%d and resolving the conflicts.", s.cfg.Ref, job.PR))
	default:
		s.post(ctx, job, fmt.Sprintf("<@%s> A slot freed up: the agent is queued to make your changes to PR #%d.",
			run.UserID, job.PR), run.UserID)
	}
}

// ReviseRequest is a /revise command, sent inside a feature thread.
type ReviseRequest struct {
	UserID   string
	UserName string
	HasRole  bool
	ThreadID string
	Text     string
}

// Revise handles /revise: dispatches a revise run on the thread's PR with the text as
// the newest instructions.
func (s *Service) Revise(ctx context.Context, req ReviseRequest, r Responder) error {
	text := strings.TrimSpace(strings.ReplaceAll(req.Text, "\r", ""))
	job, err := s.st.JobByThread(ctx, req.ThreadID)
	if errors.Is(err, store.ErrNotFound) {
		return r.Reject(ctx, "Use `/revise` inside a feature's thread.")
	} else if err != nil {
		return err
	}
	switch {
	case !req.HasRole && req.UserID != job.RequesterID:
		return r.Reject(ctx, "Only the requester or someone with the requester role can revise this.")
	case job.State != store.JobOpen:
		return r.Reject(ctx, "This feature's PR is "+job.State+", so it can't be revised.")
	case job.PR == 0:
		return r.Reject(ctx, "There's no PR to revise yet. Wait for the agent to open one.")
	}
	if n := utf8.RuneCountInString(text); n < 3 || n > maxRequest {
		return r.Reject(ctx, fmt.Sprintf("Describe the changes in 3 to %d characters.", maxRequest))
	}
	if _, err := s.st.ActiveRunForJob(ctx, job.ID); err == nil {
		return r.Reject(ctx, "The agent is already working on this or waiting to. Wait for it to finish.")
	} else if !errors.Is(err, store.ErrNotFound) {
		return err
	}
	instructions := fmt.Sprintf("From %s on Discord:\n\n%s", cleanName(req.UserName), text)
	run, err := s.reserve(ctx, req.UserID, job.ID, "revise", instructions)
	if err != nil {
		return s.rejectLimit(ctx, r, err)
	}
	if err := r.Defer(ctx); err != nil {
		s.failRun(ctx, run.ID)
		return err
	}
	if run.Status == store.RunWaiting {
		err := r.Respond(ctx, fmt.Sprintf("🔁 <@%s> asked for changes to PR #%d:\n%s\nThe agent is busy, so this is %s.",
			req.UserID, job.PR, quote(text, 1500), s.linePosition(ctx, run.ID)))
		s.drain(ctx)
		return err
	}
	if err := s.dispatch(ctx, run, job.PR, instructions); err != nil {
		return r.Respond(ctx, "❌ I couldn't start the agent. Try again later.")
	}
	return r.Respond(ctx, fmt.Sprintf("🔁 <@%s> asked for changes to PR #%d:\n%s\nThe agent is queued.",
		req.UserID, job.PR, quote(text, 1500)))
}

// CloseRequest is a /close command, sent inside a feature thread.
type CloseRequest struct {
	UserID   string
	UserName string
	HasRole  bool // the requester or approver role
	ThreadID string
}

// Close handles /close: closes the thread's PR (if any) without merging, and its issue as
// not planned. It takes the PR out of the merge queue and drops a run waiting for a slot,
// but refuses while the agent is working on it.
func (s *Service) Close(ctx context.Context, req CloseRequest, r Responder) error {
	// Hold off the merge coordinator, so the PR can't be merged while it's being closed.
	s.mergeMu.Lock()
	defer s.mergeMu.Unlock()
	job, err := s.st.JobByThread(ctx, req.ThreadID)
	if errors.Is(err, store.ErrNotFound) {
		return r.Reject(ctx, "Use `/close` inside a feature's thread.")
	} else if err != nil {
		return err
	}
	switch {
	case !req.HasRole && req.UserID != job.RequesterID:
		return r.Reject(ctx, "Only the requester or someone with the requester or approver role can close this.")
	case job.State != store.JobOpen:
		return r.Reject(ctx, "This feature is already "+job.State+".")
	}
	var waiting int64 // a run waiting for a slot, dropped on close
	if run, err := s.st.ActiveRunForJob(ctx, job.ID); err == nil {
		if run.Status != store.RunWaiting {
			return r.Reject(ctx, "The agent is working on this. Wait for it to finish, then close it.")
		}
		waiting = run.ID
	} else if !errors.Is(err, store.ErrNotFound) {
		return err
	}
	if err := r.Defer(ctx); err != nil {
		return err
	}
	if job.PR != 0 {
		pr, err := s.gh.PullRequest(ctx, job.PR)
		if err != nil {
			s.log.Error("get PR to close", "err", err, "pr", job.PR)
			return r.Respond(ctx, "❌ I couldn't check the PR on GitHub. Try again later.")
		}
		if pr.Merged {
			return r.Respond(ctx, fmt.Sprintf("PR #%d is already merged, so it can't be closed.", job.PR))
		}
	}

	now := s.cfg.Now()
	note := fmt.Sprintf("Closed from Discord by %s.", cleanName(req.UserName))
	var closed []string
	if job.PR != 0 {
		if err := s.gh.CreateComment(ctx, job.PR, note); err != nil {
			s.log.Warn("comment on closed PR", "err", err, "pr", job.PR)
		}
		if err := s.gh.ClosePullRequest(ctx, job.PR); err != nil {
			s.log.Error("close PR", "err", err, "pr", job.PR)
			return r.Respond(ctx, fmt.Sprintf("❌ I couldn't close PR #%d. Try again later.", job.PR))
		}
		closed = append(closed, fmt.Sprintf("PR #%d", job.PR))
	}
	// The PR is closed: from here on the job is, whatever happens to the issue.
	if err := s.st.SetJobState(ctx, job.ID, store.JobClosed, now); err != nil {
		return err
	}
	if waiting != 0 {
		s.failRun(ctx, waiting)
	}
	if m, err := s.st.ActiveMergeForJob(ctx, job.ID); err == nil {
		if err := s.st.UpdateMerge(ctx, m.ID, store.MergeDropped, "", "closed", now); err != nil {
			return err
		}
	} else if !errors.Is(err, store.ErrNotFound) {
		return err
	}
	issueErr := s.gh.CreateComment(ctx, job.Issue, note)
	if issueErr != nil {
		s.log.Warn("comment on closed issue", "err", issueErr, "issue", job.Issue)
	}
	if issueErr = s.gh.CloseIssue(ctx, job.Issue); issueErr != nil {
		s.log.Error("close issue", "err", issueErr, "issue", job.Issue)
	} else {
		closed = append(closed, fmt.Sprintf("issue #%d", job.Issue))
	}
	msg := fmt.Sprintf("🔒 <@%s> closed %s.", req.UserID, strings.Join(closed, " and "))
	if issueErr != nil {
		if len(closed) == 0 {
			msg = fmt.Sprintf("🔒 <@%s> closed this feature.", req.UserID)
		}
		msg += fmt.Sprintf(" I couldn't close issue #%d on GitHub; a maintainer can close it there.", job.Issue)
	}
	return r.Respond(ctx, msg)
}

func (s *Service) reserve(ctx context.Context, userID string, jobID int64, mode, instructions string) (store.Run, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.st.Reserve(ctx, userID, jobID, mode, instructions, s.cfg.Limits, s.cfg.Now())
}

func (s *Service) rejectLimit(ctx context.Context, r Responder, err error) error {
	var le *store.LimitError
	if !errors.As(err, &le) {
		return err
	}
	return r.Reject(ctx, fmt.Sprintf("You've used your %d agent runs for now. The next one frees up <t:%d:R>.",
		le.Limit, le.Retry.Unix()))
}

func (s *Service) dispatch(ctx context.Context, run store.Run, number int, instructions string) error {
	err := s.gh.Dispatch(ctx, s.cfg.Workflow, s.cfg.Ref, map[string]string{
		"number":       strconv.Itoa(number),
		"mode":         run.Mode,
		"agent":        s.cfg.Agent,
		"instructions": instructions,
		"request_id":   requestID(run.ID),
	})
	if err != nil {
		s.log.Error("dispatch", "err", err, "run", run.ID, "number", number)
		s.failRun(ctx, run.ID)
		return err
	}
	return s.setRun(ctx, run.ID, store.RunDispatched, "", 0, "")
}

func (s *Service) failRun(ctx context.Context, id int64) {
	if err := s.setRun(ctx, id, store.RunFailed, "", 0, ""); err != nil {
		s.log.Error("mark run failed", "err", err, "run", id)
	}
}

func (s *Service) setRun(ctx context.Context, id int64, status, conclusion string, wfID int64, url string) error {
	return s.st.SetRunStatus(ctx, id, status, conclusion, wfID, url, s.cfg.Now())
}

// post writes to a job's thread, if it has one. Errors are logged, not returned: a
// missed update shouldn't fail the GitHub side.
func (s *Service) post(ctx context.Context, job store.Job, content string, ping ...string) {
	if job.ThreadID == "" {
		return
	}
	if err := s.chat.Post(ctx, job.ThreadID, content, ping...); err != nil {
		s.log.Error("post to thread", "err", err, "issue", job.Issue)
	}
}

// --- GitHub events -------------------------------------------------------------------------

var (
	runTitle     = regexp.MustCompile(`^agent #\d+ \S+ \[bot-(\d+)\]$`)
	previewTitle = regexp.MustCompile(`^preview #(\d+) deploy$`)
	agentBranch  = regexp.MustCompile(`^agent/(\d+)-`)
	detailsBlock = regexp.MustCompile(`(?s)\s*<details>.*?</details>`)
	// harness/publish.sh's comment when the agent declined an implement run.
	noChanges = regexp.MustCompile("^🤖 `[^`]+` \\(`implement`\\) made no changes")
)

func requestID(runID int64) string { return "bot-" + strconv.FormatInt(runID, 10) }

var runRank = map[string]int{
	store.RunReserved: 0, store.RunDispatched: 1, store.RunQueued: 2, store.RunInProgress: 3,
	store.RunCompleted: 4, store.RunFailed: 4,
}

// WorkflowRun handles a workflow_run event or a polled run: agent runs update their bot
// run, CI runs on agent branches report to the thread.
func (s *Service) WorkflowRun(ctx context.Context, wr github.WorkflowRun) error {
	switch {
	case strings.HasSuffix(wr.Path, "/"+s.cfg.Workflow):
		return s.agentRun(ctx, wr)
	case wr.Status != "completed":
		return nil
	case strings.HasSuffix(wr.Path, "/"+s.cfg.CIWorkflow) && wr.Event == "pull_request":
		defer s.Kick()
		return s.ciRun(ctx, wr)
	case s.cfg.PreviewWorkflow != "" && strings.HasSuffix(wr.Path, "/"+s.cfg.PreviewWorkflow) &&
		wr.Event == "pull_request":
		return s.previewRun(ctx, wr)
	case wr.Event == "push" && wr.HeadBranch == s.cfg.Ref && wr.Conclusion == "success":
		switch {
		case strings.HasSuffix(wr.Path, "/"+s.cfg.CIWorkflow):
			// The base branch moved: open PRs may conflict with it now.
			return s.scheduleConflictCheck(ctx)
		case strings.HasSuffix(wr.Path, "/"+s.cfg.ServerWorkflow):
			return s.built(ctx, "server", wr.HeadSHA)
		case strings.HasSuffix(wr.Path, "/"+s.cfg.PagesWorkflow):
			return s.built(ctx, "pages", wr.HeadSHA)
		case s.cfg.APIWorkflow != "" && strings.HasSuffix(wr.Path, "/"+s.cfg.APIWorkflow):
			return s.builtAPI(ctx, wr.HeadSHA)
		}
	}
	return nil
}

func (s *Service) agentRun(ctx context.Context, wr github.WorkflowRun) error {
	m := runTitle.FindStringSubmatch(wr.DisplayTitle)
	if m == nil {
		return nil // started on GitHub, not by the bot
	}
	id, _ := strconv.ParseInt(m[1], 10, 64)
	run, err := s.st.RunByID(ctx, id)
	if errors.Is(err, store.ErrNotFound) {
		return nil
	} else if err != nil {
		return err
	}
	status := store.RunQueued
	switch wr.Status {
	case "in_progress":
		status = store.RunInProgress
	case "completed":
		status = store.RunCompleted
	}
	if runRank[status] <= runRank[run.Status] && !(status == store.RunCompleted && run.Status == store.RunFailed) {
		return nil // stale or repeated event
	}
	if err := s.setRun(ctx, run.ID, status, wr.Conclusion, wr.ID, wr.HTMLURL); err != nil {
		return err
	}
	if status == store.RunCompleted {
		defer s.drain(ctx) // a slot freed up
	}
	// Every run that gets past the gate ends with a harness comment. Say something if none
	// arrived: the gate refused the dispatch (the run still succeeds), or it was cancelled.
	if status != store.RunCompleted || run.Relayed > 0 {
		return nil
	}
	job, err := s.st.JobByID(ctx, run.JobID)
	if err != nil {
		return err
	}
	msg := fmt.Sprintf("⚠️ <@%s> The agent run ended without a result (`%s`). [Run](<%s>)",
		job.RequesterID, wr.Conclusion, wr.HTMLURL)
	if wr.Conclusion == "success" {
		msg = fmt.Sprintf("⚠️ <@%s> The workflow refused to start the agent; its gate log says why. [Run](<%s>)",
			job.RequesterID, wr.HTMLURL)
	}
	s.post(ctx, job, msg, job.RequesterID)
	return nil
}

func (s *Service) ciRun(ctx context.Context, wr github.WorkflowRun) error {
	m := agentBranch.FindStringSubmatch(wr.HeadBranch)
	if m == nil || wr.Conclusion == "cancelled" || wr.Conclusion == "skipped" {
		return nil
	}
	issue, _ := strconv.Atoi(m[1])
	job, err := s.st.JobByIssue(ctx, issue)
	if errors.Is(err, store.ErrNotFound) {
		return nil
	} else if err != nil {
		return err
	}
	if fresh, err := s.st.MarkSeen(ctx, fmt.Sprintf("ci:%d:%s", wr.ID, wr.Conclusion), s.cfg.Now()); err != nil || !fresh {
		return err
	}
	sha := short(wr.HeadSHA)
	if wr.Conclusion == "success" {
		s.ciPassed(ctx, job, wr.HeadSHA)
	} else {
		s.post(ctx, job, fmt.Sprintf("❌ CI `%s` on `%s`. [Details](<%s>)", wr.Conclusion, sha, wr.HTMLURL))
	}
	return nil
}

// previewRun posts the link to a PR's preview deployment to its thread.
func (s *Service) previewRun(ctx context.Context, wr github.WorkflowRun) error {
	t := previewTitle.FindStringSubmatch(wr.DisplayTitle)
	m := agentBranch.FindStringSubmatch(wr.HeadBranch)
	if t == nil || m == nil || wr.Conclusion != "success" || s.cfg.PreviewURL == "" {
		return nil
	}
	issue, _ := strconv.Atoi(m[1])
	job, err := s.st.JobByIssue(ctx, issue)
	if errors.Is(err, store.ErrNotFound) {
		return nil
	} else if err != nil {
		return err
	}
	if fresh, err := s.st.MarkSeen(ctx, fmt.Sprintf("preview:%d", wr.ID), s.cfg.Now()); err != nil || !fresh {
		return err
	}
	url := strings.ReplaceAll(s.cfg.PreviewURL, "{pr}", t[1])
	s.post(ctx, job, fmt.Sprintf("🔍 Preview of `%s` (offline, single player): <%s>", short(wr.HeadSHA), url))
	return nil
}

// Comment handles a comment on an issue or PR: the harness's 🤖 comments on a job are
// relayed to its thread.
func (s *Service) Comment(ctx context.Context, number int, c github.Comment) error {
	if c.User.Type != "Bot" || !strings.HasPrefix(c.Body, "🤖") {
		return nil
	}
	job, err := s.st.JobByNumber(ctx, number)
	if errors.Is(err, store.ErrNotFound) {
		return nil
	} else if err != nil {
		return err
	}
	if fresh, err := s.st.MarkSeen(ctx, "comment:"+strconv.FormatInt(c.ID, 10), s.cfg.Now()); err != nil || !fresh {
		return err
	}
	if m := s.prURL.FindStringSubmatch(c.Body); m != nil && job.PR == 0 {
		pr, _ := strconv.Atoi(m[1])
		if err := s.st.SetPR(ctx, job.ID, pr, s.cfg.Now()); err != nil {
			return err
		}
	}
	content := relayText(c.Body, c.HTMLURL)
	var ping []string
	if !strings.HasPrefix(c.Body, "🤖 Starting") {
		content = "<@" + job.RequesterID + "> " + content
		ping = []string{job.RequesterID}
	}
	s.post(ctx, job, content, ping...)
	if number == job.Issue && job.PR == 0 && job.State == store.JobOpen && noChanges.MatchString(c.Body) {
		s.closeDeclined(ctx, job)
	}
	if run, err := s.st.ActiveRunForJob(ctx, job.ID); err == nil {
		return s.st.CountRelayed(ctx, run.ID)
	}
	return nil
}

// closeDeclined closes the issue of a feature the agent declined to build: with no PR
// there is nothing left to revise, so a new request is a new /feature. Errors are logged:
// /close can still close it.
func (s *Service) closeDeclined(ctx context.Context, job store.Job) {
	if err := s.gh.CloseIssue(ctx, job.Issue); err != nil {
		s.log.Error("close declined issue", "err", err, "issue", job.Issue)
		return
	}
	if err := s.st.SetJobState(ctx, job.ID, store.JobClosed, s.cfg.Now()); err != nil {
		s.log.Error("close declined job", "err", err, "job", job.ID)
		return
	}
	s.post(ctx, job, fmt.Sprintf("🔒 I closed issue #%d since the agent made no changes. "+
		"Use `/feature` to ask again with more detail.", job.Issue))
}

// PullRequest handles pull_request events for agent branches.
func (s *Service) PullRequest(ctx context.Context, ev github.PullRequestEvent) error {
	m := agentBranch.FindStringSubmatch(ev.PullRequest.Head.Ref)
	if m == nil {
		return nil
	}
	issue, _ := strconv.Atoi(m[1])
	job, err := s.st.JobByIssue(ctx, issue)
	if errors.Is(err, store.ErrNotFound) {
		return nil
	} else if err != nil {
		return err
	}
	now := s.cfg.Now()
	switch ev.Action {
	case "synchronize":
		return s.pushed(ctx, job, ev.PullRequest.Head.SHA)
	case "opened", "reopened":
		if job.PR == 0 {
			if err := s.st.SetPR(ctx, job.ID, ev.Number, now); err != nil {
				return err
			}
		}
		if ev.Action == "reopened" {
			s.post(ctx, job, fmt.Sprintf("PR #%d was reopened.", ev.Number))
			return s.st.SetJobState(ctx, job.ID, store.JobOpen, now)
		}
	case "closed":
		defer s.Kick()
		if ev.PullRequest.Merged {
			if job.State == store.JobMerged {
				return nil // the merge coordinator merged it and said so
			}
			s.post(ctx, job, fmt.Sprintf("🎉 <@%s> PR #%d was merged. It ships with the next deploy.",
				job.RequesterID, ev.Number), job.RequesterID)
			return s.st.SetJobState(ctx, job.ID, store.JobMerged, now)
		}
		if job.State == store.JobClosed {
			return nil // closed with /close, which said so
		}
		s.post(ctx, job, fmt.Sprintf("PR #%d was closed without merging.", ev.Number))
		return s.st.SetJobState(ctx, job.ID, store.JobClosed, now)
	}
	return nil
}

// --- reconcile -----------------------------------------------------------------------------

// Reconcile catches up on anything the webhooks missed: it polls the agent workflow's runs
// and the comments on jobs with active runs, expires runs that never started, and starts
// waiting runs when slots are free.
func (s *Service) Reconcile(ctx context.Context) error {
	runs, err := s.st.ActiveRuns(ctx)
	if err != nil {
		return err
	}
	defer s.drain(ctx)
	if len(runs) == 0 {
		return nil
	}
	now := s.cfg.Now()
	oldest := runs[0].CreatedAt
	wrs, err := s.gh.WorkflowRuns(ctx, s.cfg.Workflow, oldest.Add(-time.Minute))
	if err != nil {
		return fmt.Errorf("list workflow runs: %w", err)
	}
	for i := len(wrs) - 1; i >= 0; i-- {
		if err := s.agentRun(ctx, wrs[i]); err != nil {
			return err
		}
	}
	jobs := map[int64]bool{}
	for _, r := range runs {
		if r.JobID != 0 && !jobs[r.JobID] {
			jobs[r.JobID] = true
			if err := s.pollComments(ctx, r.JobID, r.CreatedAt); err != nil {
				return err
			}
		}
		cur, err := s.st.RunByID(ctx, r.ID)
		if err != nil {
			return err
		}
		switch age := now.Sub(cur.UpdatedAt); {
		case cur.Status == store.RunReserved && age > reservedTimeout:
			s.failRun(ctx, cur.ID)
		case cur.Status == store.RunDispatched && age > dispatchedTimeout:
			s.failRun(ctx, cur.ID)
			if job, err := s.st.JobByID(ctx, cur.JobID); err == nil {
				s.post(ctx, job, fmt.Sprintf("⚠️ <@%s> The agent run never started. Try again.", job.RequesterID), job.RequesterID)
			}
		case (cur.Status == store.RunQueued || cur.Status == store.RunInProgress) && age > s.cfg.Limits.StaleAfter:
			if err := s.setRun(ctx, cur.ID, store.RunCompleted, "stale", 0, ""); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Service) pollComments(ctx context.Context, jobID int64, since time.Time) error {
	job, err := s.st.JobByID(ctx, jobID)
	if err != nil {
		return err
	}
	for _, n := range []int{job.Issue, job.PR} {
		if n == 0 {
			continue
		}
		cs, err := s.gh.Comments(ctx, n, since.Add(-time.Minute))
		if err != nil {
			return fmt.Errorf("list comments on #%d: %w", n, err)
		}
		for _, c := range cs {
			if err := s.Comment(ctx, n, c); err != nil {
				return err
			}
		}
		if job, err = s.st.JobByID(ctx, jobID); err != nil { // the PR may be known now
			return err
		}
	}
	return nil
}

// --- text ----------------------------------------------------------------------------------

// issueTitle is the request's first line, cut at a word boundary to 70 characters.
func issueTitle(text string) string {
	line, _, _ := strings.Cut(text, "\n")
	line = strings.Join(strings.Fields(line), " ")
	line = strings.TrimRight(line, ".!?:;, ")
	if utf8.RuneCountInString(line) <= 70 {
		return line
	}
	r := []rune(line)[:70]
	if i := strings.LastIndexByte(string(r), ' '); i > 40 {
		return string(r)[:i] + "…"
	}
	return string(r) + "…"
}

func threadName(issue int, title string) string {
	name := fmt.Sprintf("#%d %s", issue, title)
	if r := []rune(name); len(r) > 100 {
		name = string(r[:99]) + "…"
	}
	return name
}

// cleanName keeps a Discord display name safe to put in GitHub markdown and the
// Requested-by trailer.
func cleanName(name string) string {
	var b strings.Builder
	for _, r := range name {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == ' ' || r == '_' || r == '-' || r == '.' {
			b.WriteRune(r)
		}
	}
	out := strings.Join(strings.Fields(b.String()), " ")
	if r := []rune(out); len(r) > 32 {
		out = string(r[:32])
	}
	if out == "" {
		return "a Discord user"
	}
	return out
}

// neutralizeMentions stops "@name" in a request from pinging GitHub users.
func neutralizeMentions(s string) string { return strings.ReplaceAll(s, "@", "@\u200b") }

var mdSpecial = strings.NewReplacer(`\`, `\\`, "*", `\*`, "_", `\_`, "`", "\\`", "~", `\~`, "|", `\|`, ">", `\>`)

func escape(s string) string { return mdSpecial.Replace(s) }

// quote renders text as a Discord block quote, cut to max characters.
func quote(text string, max int) string {
	if r := []rune(text); len(r) > max {
		text = string(r[:max]) + "…"
	}
	return "> " + strings.ReplaceAll(text, "\n", "\n> ")
}

// relayText shortens a harness comment for Discord: collapsed logs become a link.
func relayText(body, url string) string {
	body = strings.ReplaceAll(body, "\r", "")
	stripped := detailsBlock.ReplaceAllString(body, "")
	link := ""
	if stripped != body {
		link = fmt.Sprintf("\n[Logs on GitHub](<%s>)", url)
	}
	stripped = strings.TrimSpace(stripped)
	if r := []rune(stripped); len(r) > 1500 {
		stripped = string(r[:1500]) + "…"
		link = fmt.Sprintf("\n[More on GitHub](<%s>)", url)
	}
	return stripped + link
}
