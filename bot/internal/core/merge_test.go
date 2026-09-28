package core

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/tfpp/the-game/bot/internal/github"
	"github.com/tfpp/the-game/bot/internal/store"
)

func (f *fakeGitHub) PullRequest(_ context.Context, n int) (github.PullRequest, error) {
	pr, ok := f.prs[n]
	if !ok {
		return github.PullRequest{}, &github.APIError{Status: 404}
	}
	return *pr, nil
}

func (f *fakeGitHub) PullRequestFiles(_ context.Context, n int) ([]string, error) {
	return f.files[n], nil
}

func (f *fakeGitHub) FileContent(_ context.Context, path, ref string) ([]byte, error) {
	if path != ".github/CODEOWNERS" || ref != "main" {
		return nil, errors.New("unexpected file")
	}
	return []byte(f.owners), nil
}

func (f *fakeGitHub) Compare(_ context.Context, base, head string) (github.Comparison, error) {
	if base == "main" {
		return github.Comparison{Status: "ahead", BehindBy: f.behind[head]}, nil
	}
	if s, ok := f.compare[base+"..."+head]; ok {
		return github.Comparison{Status: s}, nil
	}
	return github.Comparison{Status: "diverged"}, nil
}

func (f *fakeGitHub) CommitParents(_ context.Context, sha string) ([]string, error) {
	return f.parents[sha], nil
}

func (f *fakeGitHub) WorkflowRunsForSHA(_ context.Context, wf, sha string) ([]github.WorkflowRun, error) {
	switch s := f.ci[sha]; s {
	case "":
		return nil, nil
	case "pending":
		return []github.WorkflowRun{{Event: "pull_request", Status: "in_progress", HeadSHA: sha}}, nil
	default:
		return []github.WorkflowRun{{Event: "pull_request", Status: "completed", Conclusion: s, HeadSHA: sha}}, nil
	}
}

// UpdateBranch merges "main" into the PR at once: the new head is "upd-<head>".
func (f *fakeGitHub) UpdateBranch(_ context.Context, n int, head string) error {
	f.updates = append(f.updates, fmt.Sprintf("%d:%s", n, head))
	if f.updateErr != nil {
		return f.updateErr
	}
	pr := f.prs[n]
	next := "upd-" + head
	pr.Head.SHA = next
	f.parents[next] = []string{head, "mainsha"}
	f.compare["mainsha...main"] = "identical"
	f.behind[next] = 0
	f.ci[next] = "pending"
	return nil
}

func (f *fakeGitHub) SquashMerge(_ context.Context, n int, sha, title, msg string) (string, error) {
	if f.mergeErr != nil {
		return "", f.mergeErr
	}
	f.merges = append(f.merges, fmt.Sprintf("%d:%s:%s", n, sha, title))
	pr := f.prs[n]
	pr.State, pr.Merged, pr.MergeCommitSHA = "closed", true, "merged-"+sha
	return "merged-" + sha, nil
}

func (f *fakeGitHub) DeleteBranch(_ context.Context, branch string) error {
	f.deleted = append(f.deleted, branch)
	return nil
}

type fakeDeployer struct {
	requests    []string
	apiRequests []string
	deployed    string
}

func (d *fakeDeployer) DeployAPI(_ context.Context, sha string) error {
	d.apiRequests = append(d.apiRequests, sha)
	return nil
}

func (d *fakeDeployer) Deploy(_ context.Context, sha string) error {
	d.requests = append(d.requests, sha)
	return nil
}

func (d *fakeDeployer) Deployed(context.Context) (string, error) { return d.deployed, nil }

// withPR makes a feature whose agent run finished with PR pr at head, CI green.
func (e *env) withPR(t *testing.T, user string, pr int, head string) store.Job {
	t.Helper()
	ctx := context.Background()
	e.feature(t, user, fmt.Sprintf("feature for PR %d please", pr))
	runs, err := e.st.ActiveRuns(ctx)
	must(t, err)
	for _, r := range runs {
		must(t, e.st.SetRunStatus(ctx, r.ID, store.RunCompleted, "success", 0, "", e.now))
	}
	job, err := e.st.JobByIssue(ctx, 10+len(e.gh.issues))
	must(t, err)
	must(t, e.st.SetPR(ctx, job.ID, pr, e.now))
	job.PR = pr
	p := &github.PullRequest{Number: pr, Title: "feat(game): thing", State: "open"}
	p.Head.SHA, p.Head.Ref, p.Base.Ref = head, fmt.Sprintf("agent/%d-thing", job.Issue), "main"
	e.gh.prs[pr] = p
	e.gh.files[pr] = []string{"game/features/thing/feature.tscn"}
	e.gh.ci[head] = "success"
	return job
}

func (e *env) approve(t *testing.T, job store.Job, role bool, button string) *fakeResponder {
	t.Helper()
	r := &fakeResponder{}
	must(t, e.svc.Approve(context.Background(), ApproveRequest{
		UserID: "99", UserName: "Carol", HasRole: role, ThreadID: job.ThreadID, ButtonID: button,
	}, r))
	return r
}

func (e *env) mergeStatus(t *testing.T, id int64) store.Merge {
	t.Helper()
	ms, err := e.st.UnannouncedMerges(context.Background())
	must(t, err)
	q, err := e.st.MergeQueue(context.Background())
	must(t, err)
	for _, m := range append(ms, q...) {
		if m.ID == id {
			return m
		}
	}
	return store.Merge{Status: "gone"}
}

func (e *env) postsContaining(s string) int {
	n := 0
	for _, p := range e.chat.posts {
		if strings.Contains(p.content, s) {
			n++
		}
	}
	return n
}

func TestApproveAndMerge(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")

	r := e.approve(t, job, true, ApproveButtonID(12, "aaa"))
	if r.rejected != "" || !strings.Contains(r.response, "Approved `aaa`. Merging it now.") {
		t.Fatalf("approve: %+v", r)
	}
	if p := e.chat.last(); !strings.Contains(p.content, "<@99> approved `aaa`") || p.ping != "" {
		t.Errorf("thread post %+v", p)
	}
	if r := e.approve(t, job, true, ""); !strings.Contains(r.rejected, "already in the merge queue") {
		t.Errorf("second approval: %+v", r)
	}
	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.merges) != 1 || e.gh.merges[0] != "12:aaa:feat(game): thing (#12)" {
		t.Fatalf("merges %v", e.gh.merges)
	}
	if len(e.gh.deleted) != 1 || e.gh.deleted[0] != "agent/11-thing" {
		t.Errorf("deleted %v", e.gh.deleted)
	}
	job, _ = e.st.JobByID(ctx, job.ID)
	if job.State != store.JobMerged {
		t.Errorf("job %+v", job)
	}
	if p := e.chat.last(); !strings.Contains(p.content, "🎉 <@42> PR #12 was merged (approved by Carol)") || p.ping != "42" {
		t.Errorf("merged post %+v", p)
	}
	if m := e.mergeStatus(t, 1); m.Status != store.MergeMerged || m.MergedSHA != "merged-aaa" {
		t.Errorf("merge %+v", m)
	}
	// GitHub's own "merged" webhook doesn't announce it twice.
	n := len(e.chat.posts)
	ev := github.PullRequestEvent{Action: "closed", Number: 12}
	ev.PullRequest.Merged, ev.PullRequest.Head.Ref = true, "agent/11-thing"
	must(t, e.svc.PullRequest(ctx, ev))
	if len(e.chat.posts) != n {
		t.Errorf("duplicate merged post: %+v", e.chat.posts[n:])
	}
}

func TestApproveChecks(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")

	if r := e.approve(t, job, false, ""); !strings.Contains(r.rejected, "approver role") {
		t.Errorf("no role: %+v", r)
	}
	if r := e.approve(t, job, true, ApproveButtonID(12, "old")); !strings.Contains(r.response, "has changed since `old`") {
		t.Errorf("stale button: %+v", r)
	}
	if r := e.approve(t, job, true, ApproveButtonID(13, "aaa")); !strings.Contains(r.rejected, "another PR") {
		t.Errorf("other PR: %+v", r)
	}
	e.gh.ci["aaa"] = "pending"
	if r := e.approve(t, job, true, ""); !strings.Contains(r.response, "still running") {
		t.Errorf("pending CI: %+v", r)
	}
	e.gh.ci["aaa"] = "failure"
	if r := e.approve(t, job, true, ""); !strings.Contains(r.response, "CI failed") {
		t.Errorf("failed CI: %+v", r)
	}
	e.gh.ci["aaa"] = "success"
	e.gh.files[12] = []string{"game/features/x.gd", "bot/main.go", "game/project.godot"}
	if r := e.approve(t, job, true, ""); !strings.Contains(r.response, "`bot/main.go`, `game/project.godot`, which a maintainer") {
		t.Errorf("protected: %+v", r)
	}
	e.gh.files[12] = []string{"game/features/x.gd"}
	e.revise(t, job)
	if r := e.approve(t, job, true, ""); !strings.Contains(r.rejected, "agent is working") {
		t.Errorf("active run: %+v", r)
	}
	if q, _ := e.st.MergeQueue(ctx); len(q) != 0 {
		t.Errorf("queue %+v", q)
	}
	r := &fakeResponder{}
	must(t, e.svc.Approve(ctx, ApproveRequest{UserID: "1", HasRole: true, ThreadID: "nope"}, r))
	if !strings.Contains(r.rejected, "inside a feature") {
		t.Errorf("outside thread: %+v", r)
	}
}

func (e *env) revise(t *testing.T, job store.Job) {
	t.Helper()
	r := &fakeResponder{}
	must(t, e.svc.Revise(context.Background(), ReviseRequest{UserID: job.RequesterID, HasRole: true,
		ThreadID: job.ThreadID, Text: "make it red"}, r))
	if r.rejected != "" {
		t.Fatalf("revise rejected: %s", r.rejected)
	}
}

func TestMergeUpdatesABranchBehindMain(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	e.gh.behind["aaa"] = 2
	e.approve(t, job, true, "")

	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.updates) != 1 || e.gh.updates[0] != "12:aaa" || len(e.gh.merges) != 0 {
		t.Fatalf("updates %v merges %v", e.gh.updates, e.gh.merges)
	}
	if m := e.mergeStatus(t, 1); m.Status != store.MergeUpdating {
		t.Errorf("merge %+v", m)
	}
	if e.postsContaining("Bringing it up to date") != 1 {
		t.Errorf("posts %+v", e.chat.posts)
	}
	// The update's synchronize event and CI success don't drop or re-announce anything.
	ev := github.PullRequestEvent{Action: "synchronize", Number: 12}
	ev.PullRequest.Head.Ref, ev.PullRequest.Head.SHA = "agent/11-thing", "upd-aaa"
	must(t, e.svc.PullRequest(ctx, ev))
	must(t, e.svc.MergeStep(ctx)) // CI is pending on the new head
	if m := e.mergeStatus(t, 1); m.Status != store.MergeTesting || m.HeadSHA != "upd-aaa" || m.ApprovedSHA != "aaa" {
		t.Errorf("merge %+v", m)
	}
	e.gh.ci["upd-aaa"] = "success"
	must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{Path: ".github/workflows/game-ci.yml", Event: "pull_request",
		Status: "completed", Conclusion: "success", HeadBranch: "agent/11-thing", HeadSHA: "upd-aaa"}))
	if p := e.chat.last(); p.button != "" || !strings.Contains(p.content, "merge queue carries on") {
		t.Errorf("CI post during merge %+v", p)
	}
	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.merges) != 1 || !strings.HasPrefix(e.gh.merges[0], "12:upd-aaa:") {
		t.Fatalf("merges %v", e.gh.merges)
	}
}

func TestCIFailureAfterUpdateDropsTheApproval(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	e.gh.behind["aaa"] = 1
	e.approve(t, job, true, "")
	must(t, e.svc.MergeStep(ctx))
	e.gh.ci["upd-aaa"] = "failure"
	must(t, e.svc.MergeStep(ctx))
	if m := e.mergeStatus(t, 1); m.Status != "gone" {
		t.Errorf("merge still queued: %+v", m)
	}
	if p := e.chat.last(); !strings.Contains(p.content, "CI failed on `upd-aaa`") || p.ping != "42" {
		t.Errorf("post %+v", p)
	}
}

func TestNewCommitsDropTheApproval(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	other := e.withPR(t, "43", 14, "ccc")
	e.approve(t, other, true, "")
	e.gh.behind["ccc"] = 1
	e.gh.updateErr = errors.New("network") // keeps "other" at the front of the queue
	e.approve(t, job, true, "")
	e.gh.updateErr = nil

	// A push to the queued PR (not by the coordinator) voids its approval right away.
	ev := github.PullRequestEvent{Action: "synchronize", Number: 12}
	ev.PullRequest.Head.Ref, ev.PullRequest.Head.SHA = "agent/11-thing", "bbb"
	must(t, e.svc.PullRequest(ctx, ev))
	if _, err := e.st.ActiveMergeForJob(ctx, job.ID); !errors.Is(err, store.ErrNotFound) {
		t.Errorf("approval still queued: %v", err)
	}
	if e.postsContaining("New commits were pushed to PR #12") != 1 {
		t.Errorf("posts %+v", e.chat.posts)
	}
	// A head that changed without an event is caught when its turn comes.
	e.gh.prs[14].Head.SHA = "ddd"
	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.merges) != 0 || e.postsContaining("New commits were pushed to PR #14") != 1 {
		t.Errorf("merges %v posts %+v", e.gh.merges, e.chat.posts)
	}
}

func TestConflictStartsAResolveRun(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	e.approve(t, job, true, "")
	no := false
	e.gh.prs[12].Mergeable = &no

	n := len(e.gh.dispatches)
	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.dispatches) != n+1 {
		t.Fatalf("dispatches %v", e.gh.dispatches)
	}
	d := e.gh.dispatches[n]
	if d["number"] != "12" || d["mode"] != "resolve-conflicts" {
		t.Errorf("dispatch %v", d)
	}
	run, err := e.st.ActiveRunForJob(ctx, job.ID)
	if err != nil || run.UserID != autoUser {
		t.Errorf("run %+v %v", run, err)
	}
	if e.postsContaining("conflicts with main, so it left the merge queue") != 1 || e.postsContaining("resolving the conflicts") != 1 {
		t.Errorf("posts %+v", e.chat.posts)
	}
	// Same head again: no second run.
	must(t, e.st.SetRunStatus(ctx, run.ID, store.RunCompleted, "failure", 0, "", e.now))
	must(t, e.svc.scheduleConflictCheck(ctx))
	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.dispatches) != n+1 {
		t.Errorf("redispatched: %v", e.gh.dispatches[n:])
	}
}

func TestConflictWaitsForAFreeAgentSlot(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	e.feature(t, "1", "busy feature one")
	e.feature(t, "2", "busy feature two") // the agent is at its limit of 2 active runs
	no := false
	e.gh.prs[12].Mergeable = &no
	must(t, e.svc.scheduleConflictCheck(ctx))
	n := len(e.gh.dispatches)
	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.dispatches) != n || e.postsContaining("PR #12 conflicts with main now") != 1 {
		t.Fatalf("dispatches %v posts %+v", e.gh.dispatches[n:], e.chat.posts)
	}
	runs, _ := e.st.ActiveRuns(ctx)
	must(t, e.st.SetRunStatus(ctx, runs[0].ID, store.RunCompleted, "success", 0, "", e.now))
	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.dispatches) != n+1 || e.gh.dispatches[n]["mode"] != "resolve-conflicts" {
		t.Errorf("dispatches %v", e.gh.dispatches[n:])
	}
	if job, _ = e.st.JobByID(ctx, job.ID); job.ResolveSHA != "aaa" {
		t.Errorf("job %+v", job)
	}
}

func TestMergeChecksOtherPRsForConflicts(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	first := e.withPR(t, "42", 12, "aaa")
	e.withPR(t, "43", 14, "ccc")
	e.gh.prs[14].Mergeable = nil // GitHub is still computing it
	e.approve(t, first, true, "")
	must(t, e.svc.MergeStep(ctx))
	if len(e.gh.merges) != 1 || e.postsContaining("conflicts with main now") != 0 {
		t.Fatalf("merges %v", e.gh.merges)
	}
	no := false
	e.gh.prs[14].Mergeable = &no
	must(t, e.svc.MergeStep(ctx))
	if e.postsContaining("<@43> PR #14 conflicts with main now") != 1 {
		t.Errorf("posts %+v", e.chat.posts)
	}
	must(t, e.svc.MergeStep(ctx)) // the check is done; nothing more
	if e.postsContaining("PR #14 conflicts with main now") != 1 {
		t.Errorf("posts %+v", e.chat.posts)
	}
}

func TestCIPassedOffersTheApproveButton(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.withPR(t, "42", 12, "aaa")
	ci := github.WorkflowRun{ID: 1, Path: ".github/workflows/game-ci.yml", Event: "pull_request", Status: "completed",
		Conclusion: "success", HeadBranch: "agent/11-thing", HeadSHA: "aaa"}
	must(t, e.svc.WorkflowRun(ctx, ci))
	if p := e.chat.last(); p.button != "approve:12:aaa" || !strings.Contains(p.content, "CI passed on `aaa`") {
		t.Errorf("post %+v", p)
	}
	e.gh.files[12] = []string{".github/workflows/x.yml"}
	ci.ID = 2
	must(t, e.svc.WorkflowRun(ctx, ci))
	if p := e.chat.last(); p.button != "" || !strings.Contains(p.content, "a maintainer has to review") {
		t.Errorf("protected post %+v", p)
	}
}

func TestDeployAfterBothBuilds(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	build := func(wf, sha string) {
		must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{Path: ".github/workflows/" + wf, Event: "push",
			Status: "completed", Conclusion: "success", HeadBranch: "main", HeadSHA: sha}))
	}
	build("server-image.yml", "s1")
	if len(e.deploy.requests) != 0 {
		t.Fatalf("deployed before pages: %v", e.deploy.requests)
	}
	build("pages.yml", "s1")
	if len(e.deploy.requests) != 1 || e.deploy.requests[0] != "s1" {
		t.Fatalf("requests %v", e.deploy.requests)
	}
	// An older build finishing late doesn't roll back.
	e.gh.compare["s1...s0"] = "behind"
	build("server-image.yml", "s0")
	build("pages.yml", "s0")
	e.gh.compare["s1...s2"] = "ahead"
	build("server-image.yml", "s2")
	build("pages.yml", "s2")
	if strings.Join(e.deploy.requests, ",") != "s1,s2" {
		t.Errorf("requests %v", e.deploy.requests)
	}

	// Once the host reports a deploy, merged PRs it contains are announced once.
	job := e.withPR(t, "42", 12, "aaa")
	e.approve(t, job, true, "")
	must(t, e.svc.MergeStep(ctx))
	e.deploy.deployed = "s2"
	e.gh.compare["merged-aaa...s2"] = "diverged"
	must(t, e.svc.MergeStep(ctx))
	if e.postsContaining("is live") != 0 {
		t.Fatalf("announced too early")
	}
	e.deploy.deployed = "s3"
	e.gh.compare["merged-aaa...s3"] = "ahead"
	must(t, e.svc.MergeStep(ctx))
	must(t, e.svc.MergeStep(ctx))
	if e.postsContaining("🚀 PR #12 is live") != 1 {
		t.Errorf("posts %+v", e.chat.posts)
	}
}

func TestDeployAPIAfterItsBuild(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	build := func(wf, branch, conclusion, sha string) {
		must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{Path: ".github/workflows/" + wf, Event: "push",
			Status: "completed", Conclusion: conclusion, HeadBranch: branch, HeadSHA: sha}))
	}
	build("api-image.yml", "feat/x", "success", "a0")
	build("api-image.yml", "main", "failure", "a0")
	if len(e.deploy.apiRequests) != 0 {
		t.Fatalf("deployed a branch or failed build: %v", e.deploy.apiRequests)
	}
	build("api-image.yml", "main", "success", "a1")
	build("api-image.yml", "main", "success", "a1") // redelivered event
	// An older build finishing late doesn't roll back.
	e.gh.compare["a1...a0"] = "behind"
	build("api-image.yml", "main", "success", "a0")
	e.gh.compare["a1...a2"] = "ahead"
	build("api-image.yml", "main", "success", "a2")
	if strings.Join(e.deploy.apiRequests, ",") != "a1,a2" {
		t.Errorf("api requests %v", e.deploy.apiRequests)
	}
	if len(e.deploy.requests) != 0 {
		t.Errorf("an API build deployed the game server: %v", e.deploy.requests)
	}
}

func TestQueue(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	if s, _ := e.svc.Queue(ctx, "agent"); s != "No agent runs are active." {
		t.Errorf("empty agent queue %q", s)
	}
	if s, _ := e.svc.Queue(ctx, "merge"); s != "The merge queue is empty." {
		t.Errorf("empty merge queue %q", s)
	}
	job := e.withPR(t, "42", 12, "aaa")
	e.feature(t, "7", "add a scoreboard")
	s, err := e.svc.Queue(ctx, "agent")
	must(t, err)
	if !strings.Contains(s, "1 active, at most 2 at once") || !strings.Contains(s, "issue #12 add a scoreboard (<#thread2>) · implement · dispatched · by <@7>") {
		t.Errorf("agent queue %q", s)
	}
	e.gh.behind["aaa"] = 1
	e.approve(t, job, true, "")
	must(t, e.svc.MergeStep(ctx))
	s, err = e.svc.Queue(ctx, "merge")
	must(t, err)
	if !strings.Contains(s, "1. PR #12 feature for PR 12 please (<#thread1>) · updating with main · approved by <@99>") {
		t.Errorf("merge queue %q", s)
	}
}

func TestProtectedPaths(t *testing.T) {
	pats := codeownersPatterns("# comment\n/.github/ @a\n\n/game/core/net/ @a\n/game/project.godot @a\n")
	files := []string{"game/features/a.gd", "game/core/net/n.gd", "game/project.godot", ".github/x", "game/project.godot.bak", "game/core/netx"}
	got := strings.Join(protectedPaths(files, pats), " ")
	if got != "game/core/net/n.gd game/project.godot .github/x" {
		t.Errorf("got %q", got)
	}
}
