package core

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/tfpp/the-game/bot/internal/github"
	"github.com/tfpp/the-game/bot/internal/store"
)

type fakeGitHub struct {
	issues      []string // "title\x00body"
	dispatches  []map[string]string
	runs        []github.WorkflowRun
	comments    map[int][]github.Comment
	failIssue   bool
	failDispach bool

	// Closing.
	newComments  []string // "n:body"
	closedIssues []int
	closedPRs    []int
	closeErr     error

	// Merging (merge_test.go).
	prs       map[int]*github.PullRequest
	files     map[int][]string
	owners    string
	ci        map[string]string   // head SHA -> success, failure, pending
	behind    map[string]int      // head SHA -> commits behind the base
	compare   map[string]string   // "base...head" -> status
	parents   map[string][]string // commit -> parents
	updateErr error
	updates   []string // "pr:expected head"
	merges    []string // "pr:sha:title"
	mergeErr  error
	deleted   []string

	// Releases (release_test.go).
	releases     []github.Release
	releaseCalls int
	contents     map[string]string // "path@ref" -> file content
}

func (f *fakeGitHub) CreateIssue(_ context.Context, title, body string) (github.Issue, error) {
	if f.failIssue {
		return github.Issue{}, errors.New("boom")
	}
	f.issues = append(f.issues, title+"\x00"+body)
	n := 10 + len(f.issues)
	return github.Issue{Number: n, Title: title, HTMLURL: fmt.Sprintf("https://github.com/o/r/issues/%d", n)}, nil
}

func (f *fakeGitHub) Dispatch(_ context.Context, wf, ref string, in map[string]string) error {
	if f.failDispach {
		return errors.New("boom")
	}
	f.dispatches = append(f.dispatches, in)
	return nil
}

func (f *fakeGitHub) WorkflowRuns(context.Context, string, time.Time) ([]github.WorkflowRun, error) {
	return f.runs, nil
}

func (f *fakeGitHub) Comments(_ context.Context, n int, _ time.Time) ([]github.Comment, error) {
	return f.comments[n], nil
}

func (f *fakeGitHub) CreateComment(_ context.Context, n int, body string) error {
	f.newComments = append(f.newComments, fmt.Sprintf("%d:%s", n, body))
	return nil
}

func (f *fakeGitHub) CloseIssue(_ context.Context, n int) error {
	if f.closeErr != nil {
		return f.closeErr
	}
	f.closedIssues = append(f.closedIssues, n)
	return nil
}

func (f *fakeGitHub) ClosePullRequest(_ context.Context, n int) error {
	if f.closeErr != nil {
		return f.closeErr
	}
	f.closedPRs = append(f.closedPRs, n)
	if pr := f.prs[n]; pr != nil {
		pr.State = "closed"
	}
	return nil
}

type post struct{ thread, content, ping, button string }

type fakeChat struct{ posts []post }

func (c *fakeChat) PostButton(_ context.Context, thread, content, _, id string) error {
	c.posts = append(c.posts, post{thread: thread, content: content, button: id})
	return nil
}

func (c *fakeChat) Post(_ context.Context, thread, content string, ping ...string) error {
	c.posts = append(c.posts, post{thread: thread, content: content, ping: strings.Join(ping, ",")})
	return nil
}

func (c *fakeChat) last() post {
	if len(c.posts) == 0 {
		return post{}
	}
	return c.posts[len(c.posts)-1]
}

type fakeResponder struct {
	rejected, response string
	deferred           bool
	threads            int
	counter            *int // shared across responders so thread IDs are unique
}

func (r *fakeResponder) Reject(_ context.Context, msg string) error {
	if r.deferred {
		panic("reject after defer")
	}
	r.rejected = msg
	return nil
}
func (r *fakeResponder) Defer(context.Context) error { r.deferred = true; return nil }
func (r *fakeResponder) Respond(_ context.Context, c string) error {
	r.response = c
	return nil
}
func (r *fakeResponder) Thread(context.Context, string) (string, error) {
	r.threads++
	if r.counter == nil {
		r.counter = new(int)
	}
	*r.counter++
	return fmt.Sprintf("thread%d", *r.counter), nil
}

type env struct {
	deploy *fakeDeployer
	svc    *Service
	st     *store.Store
	gh     *fakeGitHub
	chat   *fakeChat
	now    time.Time
	nth    int
}

func newEnv(t *testing.T) *env {
	t.Helper()
	st, err := store.Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	e := &env{deploy: &fakeDeployer{}, st: st, gh: &fakeGitHub{comments: map[int][]github.Comment{}, prs: map[int]*github.PullRequest{},
		files: map[int][]string{}, contents: map[string]string{}, ci: map[string]string{}, behind: map[string]int{}, compare: map[string]string{},
		parents: map[string][]string{}, owners: "/.github/ @x\n/bot/ @x\n/game/project.godot @x\n"}, chat: &fakeChat{},
		now: time.Unix(1_800_000_000, 0)}
	e.svc = New(Config{
		Repo: "o/r", Ref: "main", Workflow: "agent.yml", CIWorkflow: "game-ci.yml", Agent: "claude",
		ServerWorkflow: "server-image.yml", PagesWorkflow: "pages.yml", APIWorkflow: "api-image.yml", Deployer: e.deploy,
		PreviewWorkflow: "preview.yml", PreviewURL: "https://pr-{pr}.example.dev/",
		ReleaseChannelID: "releases",
		Limits:           store.Limits{PerUser: 2, Window: 24 * time.Hour, MaxActive: 2, StaleAfter: 3 * time.Hour},
		Now:              func() time.Time { return e.now },
		Logger:           slog.New(slog.DiscardHandler),
	}, st, e.gh, e.chat)
	return e
}

func (e *env) feature(t *testing.T, user, text string) *fakeResponder {
	t.Helper()
	r := &fakeResponder{counter: &e.nth}
	err := e.svc.Feature(context.Background(), FeatureRequest{
		UserID: user, UserName: "Al@ice*", HasRole: true, ChannelID: "c1", Text: text,
	}, r)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func (e *env) runStatus(t *testing.T, id int64) store.Run {
	t.Helper()
	r, err := e.st.RunByID(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestFeatureOpensIssueThreadAndDispatches(t *testing.T) {
	e := newEnv(t)
	r := e.feature(t, "42", "Add jump pads that launch players upward.\nMake them glow.")
	if r.rejected != "" {
		t.Fatalf("rejected: %s", r.rejected)
	}
	title, body, _ := strings.Cut(e.gh.issues[0], "\x00")
	if title != "Add jump pads that launch players upward" {
		t.Errorf("title %q", title)
	}
	if !strings.HasSuffix(body, "\n\nRequested-by: Alice <discord:42>\n") {
		t.Errorf("body lacks trailer: %q", body)
	}
	d := e.gh.dispatches[0]
	if d["number"] != "11" || d["mode"] != "implement" || d["agent"] != "claude" || d["request_id"] != "bot-1" {
		t.Errorf("dispatch %v", d)
	}
	if !strings.Contains(r.response, "[issue #11]") || r.threads != 1 {
		t.Errorf("response %q threads %d", r.response, r.threads)
	}
	job, err := e.st.JobByThread(context.Background(), "thread1")
	if err != nil || job.Issue != 11 || job.RequesterID != "42" {
		t.Fatalf("job %+v %v", job, err)
	}
	if p := e.chat.last(); p.thread != "thread1" || p.ping != "42" {
		t.Errorf("thread post %+v", p)
	}
	if run := e.runStatus(t, 1); run.Status != store.RunDispatched || run.JobID != job.ID {
		t.Errorf("run %+v", run)
	}
}

func TestFeatureChecks(t *testing.T) {
	e := newEnv(t)
	r := &fakeResponder{}
	e.svc.Feature(context.Background(), FeatureRequest{UserID: "1", Text: "long enough text", HasRole: false}, r)
	if !strings.Contains(r.rejected, "role") {
		t.Errorf("no role: %q", r.rejected)
	}
	if r := e.feature(t, "1", "short"); !strings.Contains(r.rejected, "characters") {
		t.Errorf("short: %q", r.rejected)
	}
	e.feature(t, "1", "first feature request")
	e.feature(t, "1", "second feature request")
	if r := e.feature(t, "1", "third feature request"); !strings.Contains(r.rejected, "your 2 agent runs") {
		t.Errorf("per-user limit: %q", r.rejected)
	}
	if len(e.gh.issues) != 2 {
		t.Errorf("issues opened: %d", len(e.gh.issues))
	}
}

func TestFeaturesWaitForAFreeSlot(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "1", "first feature request")
	e.feature(t, "2", "second feature request")
	for _, u := range []string{"3", "4", "5"} {
		if r := e.feature(t, u, "a feature while the agent is busy"); r.rejected != "" {
			t.Fatalf("rejected: %q", r.rejected)
		}
	}
	if len(e.gh.issues) != 5 || len(e.gh.dispatches) != 2 {
		t.Fatalf("issues %d dispatches %d", len(e.gh.issues), len(e.gh.dispatches))
	}
	if e.postsContaining("next in line") != 1 || e.postsContaining("number 3 in line") != 1 {
		t.Errorf("posts %+v", e.chat.posts)
	}
	if q, _ := e.svc.Queue(ctx, "agent"); !strings.Contains(q, "2 active, at most 2 at once, 3 waiting") {
		t.Errorf("queue %q", q)
	}
	// A finished run frees a slot for the oldest waiting feature.
	must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #11 implement [bot-1]", Status: "completed", Conclusion: "success"}))
	if len(e.gh.dispatches) != 3 || e.gh.dispatches[2]["number"] != "13" || e.gh.dispatches[2]["request_id"] != "bot-3" {
		t.Fatalf("dispatches %v", e.gh.dispatches)
	}
	if p := e.chat.last(); p.thread != "thread3" || !strings.Contains(p.content, "A slot freed up") || p.ping != "3" {
		t.Errorf("post %+v", p)
	}
	// A run that never starts frees its slot too, on the next reconcile.
	e.now = e.now.Add(20 * time.Minute)
	must(t, e.svc.Reconcile(ctx))
	if len(e.gh.dispatches) != 5 {
		t.Errorf("dispatches %v", e.gh.dispatches)
	}
}

func TestFeatureIssueFailureFreesTheSlot(t *testing.T) {
	e := newEnv(t)
	e.gh.failIssue = true
	r := e.feature(t, "1", "a feature request")
	if !strings.Contains(r.response, "couldn't open") {
		t.Errorf("response %q", r.response)
	}
	if run := e.runStatus(t, 1); run.Status != store.RunFailed {
		t.Errorf("run %+v", run)
	}
	e.gh.failIssue = false
	e.feature(t, "1", "a feature request")
	if r := e.feature(t, "1", "a feature request"); r.rejected != "" {
		t.Errorf("failed runs should not count: %q", r.rejected)
	}
}

func TestNoChangesClosesTheIssue(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	bot := github.User{Login: "the-game[bot]", Type: "Bot"}
	body := "🤖 `claude` (`implement`) made no changes ([run](https://run) · 1.2M tokens (34k output) · ~$3.46).\n\nThis is unclear."
	must(t, e.svc.Comment(ctx, 11, github.Comment{ID: 1, User: bot, Body: body}))
	if fmt.Sprint(e.gh.closedIssues) != "[11]" {
		t.Errorf("closed %v", e.gh.closedIssues)
	}
	job, _ := e.st.JobByIssue(ctx, 11)
	if job.State != store.JobClosed || !strings.Contains(e.chat.last().content, "closed issue #11") {
		t.Errorf("job %+v post %+v", job, e.chat.last())
	}
	if len(e.chat.posts) < 2 || !strings.Contains(e.chat.posts[len(e.chat.posts)-2].content, "made no changes") {
		t.Errorf("comment not relayed first: %+v", e.chat.posts)
	}
}

func TestNoChangesOnARevisionKeepsTheIssue(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	job, _ := e.st.JobByIssue(ctx, 11)
	must(t, e.st.SetPR(ctx, job.ID, 12, e.now))
	bot := github.User{Login: "the-game[bot]", Type: "Bot"}
	must(t, e.svc.Comment(ctx, 12, github.Comment{ID: 1, User: bot, Body: "🤖 `claude` (`revise`) made no changes (x)."}))
	must(t, e.svc.Comment(ctx, 11, github.Comment{ID: 2, User: bot, Body: "🤖 `claude` (`implement`) made no changes (x)."}))
	job, _ = e.st.JobByIssue(ctx, 11)
	if len(e.gh.closedIssues) != 0 || job.State != store.JobOpen {
		t.Errorf("closed %v, job %+v", e.gh.closedIssues, job)
	}
}

func TestWorkflowRunAndCommentsReachTheThread(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	bot := github.User{Login: "github-actions[bot]", Type: "Bot"}
	agentRun := github.WorkflowRun{ID: 900, Path: ".github/workflows/agent.yml", DisplayTitle: "agent #11 implement [bot-1]",
		Status: "in_progress", HTMLURL: "https://run"}

	must(t, e.svc.WorkflowRun(ctx, agentRun))
	if run := e.runStatus(t, 1); run.Status != store.RunInProgress || run.WorkflowRunID != 900 {
		t.Errorf("run %+v", run)
	}
	n := len(e.chat.posts)
	must(t, e.svc.Comment(ctx, 11, github.Comment{ID: 1, User: bot, Body: "🤖 Starting `claude`"}))
	must(t, e.svc.Comment(ctx, 11, github.Comment{ID: 1, User: bot, Body: "🤖 Starting `claude`"}))
	must(t, e.svc.Comment(ctx, 11, github.Comment{ID: 2, User: github.User{Type: "User"}, Body: "🤖 human"}))
	if len(e.chat.posts) != n+1 || e.chat.last().ping != "" {
		t.Fatalf("posts %+v", e.chat.posts[n:])
	}
	must(t, e.svc.Comment(ctx, 11, github.Comment{ID: 3, User: bot, Body: "🤖 Opened https://github.com/o/r/pull/12 · 1.2M tokens (34k output) · ~$3.46\n"}))
	if p := e.chat.last(); !strings.HasPrefix(p.content, "<@42> 🤖 Opened") || p.ping != "42" {
		t.Errorf("opened post %+v", p)
	}
	job, _ := e.st.JobByIssue(ctx, 11)
	if job.PR != 12 {
		t.Errorf("PR not recorded: %+v", job)
	}
	// Comments on the PR reach the same thread.
	must(t, e.svc.Comment(ctx, 12, github.Comment{ID: 4, User: bot, Body: "🤖 Pushed abc\n<details>log</details>"}))
	if p := e.chat.last(); !strings.Contains(p.content, "[Logs on GitHub]") || strings.Contains(p.content, "details") {
		t.Errorf("details not stripped: %q", p.content)
	}

	agentRun.Status, agentRun.Conclusion = "completed", "success"
	n = len(e.chat.posts)
	must(t, e.svc.WorkflowRun(ctx, agentRun))
	agentRun.Status = "in_progress" // late event must not move it back
	must(t, e.svc.WorkflowRun(ctx, agentRun))
	if run := e.runStatus(t, 1); run.Status != store.RunCompleted || run.Conclusion != "success" {
		t.Errorf("run %+v", run)
	}
	if len(e.chat.posts) != n {
		t.Errorf("success should not post: %+v", e.chat.posts[n:])
	}

	ci := github.WorkflowRun{ID: 5, Path: ".github/workflows/game-ci.yml", Event: "pull_request", Status: "completed",
		Conclusion: "failure", HeadBranch: "agent/11-add-jump-pads-please", HeadSHA: "abcdef123", HTMLURL: "https://ci"}
	must(t, e.svc.WorkflowRun(ctx, ci))
	must(t, e.svc.WorkflowRun(ctx, ci))
	if len(e.chat.posts) != n+1 || !strings.Contains(e.chat.last().content, "CI `failure` on `abcdef1`") {
		t.Errorf("ci posts %+v", e.chat.posts[n:])
	}
}

func TestPreviewDeployReachesTheThread(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	run := github.WorkflowRun{ID: 7, Path: ".github/workflows/preview.yml", Event: "pull_request",
		DisplayTitle: "preview #12 deploy", Status: "completed", Conclusion: "success",
		HeadBranch: "agent/11-add-jump-pads-please", HeadSHA: "abcdef123"}
	n := len(e.chat.posts)
	for _, wr := range []github.WorkflowRun{
		{ID: 1, Path: run.Path, Event: run.Event, DisplayTitle: "preview #12 cleanup", Status: "completed",
			Conclusion: "success", HeadBranch: run.HeadBranch},
		{ID: 2, Path: run.Path, Event: run.Event, DisplayTitle: run.DisplayTitle, Status: "completed",
			Conclusion: "failure", HeadBranch: run.HeadBranch},
		{ID: 3, Path: run.Path, Event: run.Event, DisplayTitle: run.DisplayTitle, Status: "in_progress",
			HeadBranch: run.HeadBranch},
		{ID: 4, Path: run.Path, Event: run.Event, DisplayTitle: "preview #50 deploy", Status: "completed",
			Conclusion: "success", HeadBranch: "ci/pr-previews"},
	} {
		must(t, e.svc.WorkflowRun(ctx, wr))
	}
	if len(e.chat.posts) != n {
		t.Fatalf("unexpected posts %+v", e.chat.posts[n:])
	}
	must(t, e.svc.WorkflowRun(ctx, run))
	must(t, e.svc.WorkflowRun(ctx, run)) // redelivered
	if len(e.chat.posts) != n+1 {
		t.Fatalf("posts %+v", e.chat.posts[n:])
	}
	if p := e.chat.last(); p.thread != "thread1" || p.ping != "" ||
		p.content != "🔍 Preview of `abcdef1` (offline, single player): <https://pr-12.example.dev/>" {
		t.Errorf("post %+v", p)
	}
}

func TestCancelledRunWithoutCommentsIsReported(t *testing.T) {
	e := newEnv(t)
	e.feature(t, "42", "add jump pads please")
	must(t, e.svc.WorkflowRun(context.Background(), github.WorkflowRun{ID: 1, Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #11 implement [bot-1]", Status: "completed", Conclusion: "cancelled", HTMLURL: "https://run"}))
	if p := e.chat.last(); !strings.Contains(p.content, "`cancelled`") || p.ping != "42" {
		t.Errorf("post %+v", p)
	}
}

func TestRunRefusedByTheGateIsReported(t *testing.T) {
	e := newEnv(t)
	e.feature(t, "42", "add jump pads please")
	// The gate refused it: the workflow succeeds, but no harness comment arrives.
	must(t, e.svc.WorkflowRun(context.Background(), github.WorkflowRun{ID: 1, Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #11 implement [bot-1]", Status: "completed", Conclusion: "success", HTMLURL: "https://run"}))
	if p := e.chat.last(); !strings.Contains(p.content, "refused to start") || p.ping != "42" {
		t.Errorf("post %+v", p)
	}
}

func TestRevise(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	revise := func(user string, role bool, text string) *fakeResponder {
		r := &fakeResponder{}
		must(t, e.svc.Revise(ctx, ReviseRequest{UserID: user, UserName: "Bob", HasRole: role, ThreadID: "thread1", Text: text}, r))
		return r
	}
	if r := revise("42", true, "make them red"); !strings.Contains(r.rejected, "no PR") {
		t.Errorf("before PR: %q", r.rejected)
	}
	job, _ := e.st.JobByIssue(ctx, 11)
	must(t, e.st.SetPR(ctx, job.ID, 12, e.now))
	if r := revise("42", true, "make them red"); !strings.Contains(r.rejected, "already working") {
		t.Errorf("active run: %q", r.rejected)
	}
	must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #11 implement [bot-1]", Status: "completed", Conclusion: "success"}))
	if r := revise("7", false, "make them red"); !strings.Contains(r.rejected, "Only the requester") {
		t.Errorf("stranger: %q", r.rejected)
	}
	r := revise("7", true, "make them red")
	if r.rejected != "" || !strings.Contains(r.response, "changes to PR #12") {
		t.Fatalf("revise: %+v", r)
	}
	d := e.gh.dispatches[len(e.gh.dispatches)-1]
	if d["number"] != "12" || d["mode"] != "revise" || d["instructions"] != "From Bob on Discord:\n\nmake them red" || d["request_id"] != "bot-2" {
		t.Errorf("dispatch %v", d)
	}
	r = &fakeResponder{}
	must(t, e.svc.Revise(ctx, ReviseRequest{UserID: "42", HasRole: true, ThreadID: "elsewhere", Text: "x y z"}, r))
	if !strings.Contains(r.rejected, "inside a feature") {
		t.Errorf("outside thread: %q", r.rejected)
	}
}

func TestPullRequestClosed(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	ev := github.PullRequestEvent{Action: "closed", Number: 12}
	ev.PullRequest.Merged = true
	ev.PullRequest.Head.Ref = "agent/11-add-jump-pads-please"
	must(t, e.svc.PullRequest(ctx, ev))
	job, _ := e.st.JobByIssue(ctx, 11)
	if job.State != store.JobMerged || !strings.Contains(e.chat.last().content, "merged") {
		t.Errorf("job %+v post %+v", job, e.chat.last())
	}
}

func TestReconcile(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	e.feature(t, "43", "add a scoreboard")
	e.gh.runs = []github.WorkflowRun{{ID: 1, Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #11 implement [bot-1]", Status: "completed", Conclusion: "failure"}}
	e.gh.comments[11] = []github.Comment{{ID: 9, User: github.User{Type: "Bot"}, Body: "🤖 `claude` did not produce a change"}}
	e.now = e.now.Add(20 * time.Minute)
	must(t, e.svc.Reconcile(ctx))
	if run := e.runStatus(t, 1); run.Status != store.RunCompleted || run.Conclusion != "failure" {
		t.Errorf("run 1 %+v", run)
	}
	if run := e.runStatus(t, 2); run.Status != store.RunFailed {
		t.Errorf("run 2 should have expired: %+v", run)
	}
	var relayed, lost bool
	for _, p := range e.chat.posts {
		relayed = relayed || (p.thread == "thread1" && strings.Contains(p.content, "did not produce"))
		lost = lost || (p.thread == "thread2" && strings.Contains(p.content, "never started"))
	}
	if !relayed || !lost {
		t.Errorf("posts %+v", e.chat.posts)
	}
}

func TestText(t *testing.T) {
	long := strings.Repeat("word ", 30)
	if got := issueTitle(long); len([]rune(got)) > 71 || !strings.HasSuffix(got, "…") {
		t.Errorf("title %q", got)
	}
	if got := cleanName("<@here> **Bob**\n"); got != "here Bob" {
		t.Errorf("cleanName %q", got)
	}
	if got := cleanName("🙂"); got != "a Discord user" {
		t.Errorf("cleanName empty %q", got)
	}
	if got := neutralizeMentions("ping @octocat"); got != "ping @\u200boctocat" {
		t.Errorf("mentions %q", got)
	}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func TestReviseWaitsForAFreeSlot(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	job, _ := e.st.JobByIssue(ctx, 11)
	must(t, e.st.SetPR(ctx, job.ID, 12, e.now))
	must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #11 implement [bot-1]", Status: "completed", Conclusion: "success"}))
	e.feature(t, "1", "busy feature one")
	e.feature(t, "2", "busy feature two")
	r := &fakeResponder{}
	must(t, e.svc.Revise(ctx, ReviseRequest{UserID: "42", UserName: "Bob", HasRole: true, ThreadID: "thread1", Text: "make them red"}, r))
	if r.rejected != "" || !strings.Contains(r.response, "next in line") {
		t.Fatalf("revise %+v", r)
	}
	r = &fakeResponder{}
	must(t, e.svc.Revise(ctx, ReviseRequest{UserID: "42", UserName: "Bob", HasRole: true, ThreadID: "thread1", Text: "and blue"}, r))
	if !strings.Contains(r.rejected, "waiting") {
		t.Errorf("second revise: %q", r.rejected)
	}
	n := len(e.gh.dispatches)
	must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #13 implement [bot-2]", Status: "completed", Conclusion: "success"}))
	if len(e.gh.dispatches) != n+1 {
		t.Fatalf("dispatches %v", e.gh.dispatches)
	}
	if d := e.gh.dispatches[n]; d["number"] != "12" || d["mode"] != "revise" || d["instructions"] != "From Bob on Discord:\n\nmake them red" {
		t.Errorf("dispatch %v", d)
	}
}
