package core

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/tfpp/the-game/bot/internal/github"
	"github.com/tfpp/the-game/bot/internal/store"
)

func (e *env) closedThreads() string { return fmt.Sprint(e.chat.closed) }

func TestCloseCommandClosesTheThread(t *testing.T) {
	e := newEnv(t)
	job := e.withPR(t, "42", 12, "aaa")
	if r := e.close(t, job, "42", false); r.rejected != "" {
		t.Fatalf("close: %+v", r)
	}
	if e.closedThreads() != "[thread1]" {
		t.Errorf("closed threads %s", e.closedThreads())
	}
}

func TestPRClosedWithoutMergingClosesTheThread(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	ev := github.PullRequestEvent{Action: "closed", Number: 12}
	ev.PullRequest.Head.Ref = "agent/11-thing"
	must(t, e.svc.PullRequest(ctx, ev))
	if p := e.chat.last(); p.embed == nil || p.embed.Title != "🔒 PR closed" {
		t.Errorf("post %+v", p)
	}
	if e.closedThreads() != "[thread1]" {
		t.Errorf("closed threads %s", e.closedThreads())
	}
	// Reopening posts in the thread, which reopens it.
	ev.Action = "reopened"
	must(t, e.svc.PullRequest(ctx, ev))
	job, _ = e.st.JobByID(ctx, job.ID)
	if job.State != store.JobOpen || e.chat.last().embed.Title != "↩️ PR reopened" {
		t.Errorf("job %+v post %+v", job, e.chat.last())
	}
}

func TestQueuedMergeClosesTheThreadOnceDeployed(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	e.approve(t, job, true, "")
	must(t, e.svc.MergeStep(ctx))
	if len(e.chat.closed) != 0 {
		t.Fatalf("closed on merge, before the deploy: %s", e.closedThreads())
	}
	e.deploy.deployed = "s1"
	e.gh.compare["merged-aaa...s1"] = "behind"
	must(t, e.svc.MergeStep(ctx))
	if len(e.chat.closed) != 0 {
		t.Fatalf("closed before a deploy contains it: %s", e.closedThreads())
	}
	e.deploy.deployed = "s2"
	e.gh.compare["merged-aaa...s2"] = "ahead"
	must(t, e.svc.MergeStep(ctx))
	must(t, e.svc.MergeStep(ctx))
	if e.postsContaining("🚀 Live") != 1 || e.closedThreads() != "[thread1]" {
		t.Errorf("closed threads %s posts %+v", e.closedThreads(), e.chat.posts)
	}
}

func TestGitHubMergeClosesTheThreadOnceDeployed(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	ev := github.PullRequestEvent{Action: "closed", Number: 12}
	ev.PullRequest.Merged, ev.PullRequest.MergeCommitSHA, ev.PullRequest.Head.Ref = true, "gh-merge", "agent/11-thing"
	must(t, e.svc.PullRequest(ctx, ev))
	must(t, e.svc.PullRequest(ctx, ev)) // a redelivery changes nothing
	if e.postsContaining("🎉 PR merged") != 1 || len(e.chat.closed) != 0 {
		t.Fatalf("posts %+v closed %s", e.chat.posts, e.closedThreads())
	}
	job, _ = e.st.JobByID(ctx, job.ID)
	if job.State != store.JobMerged {
		t.Errorf("job %+v", job)
	}
	e.deploy.deployed = "s1"
	e.gh.compare["gh-merge...s1"] = "ahead"
	must(t, e.svc.MergeStep(ctx))
	if e.postsContaining("🚀 Live\nPR #12 is live") != 1 || e.closedThreads() != "[thread1]" {
		t.Errorf("closed threads %s posts %+v", e.closedThreads(), e.chat.posts)
	}
}

func TestDeclinedFeatureClosesTheThread(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	bot := github.User{Login: "the-game[bot]", Type: "Bot"}
	must(t, e.svc.Comment(ctx, 11, github.Comment{ID: 1, User: bot, Body: "🤖 `claude` (`implement`) made no changes (x)."}))
	if e.closedThreads() != "[thread1]" {
		t.Errorf("closed threads %s", e.closedThreads())
	}
}

func TestIssueClosedOnGitHub(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "1", "first feature please")
	e.feature(t, "2", "second feature please")
	e.feature(t, "3", "third feature waits") // MaxActive is 2

	// The agent is working on issue 11: its result decides.
	must(t, e.svc.Issue(ctx, "closed", 11))
	if job, _ := e.st.JobByIssue(ctx, 11); job.State != store.JobOpen || len(e.chat.closed) != 0 {
		t.Fatalf("closed during a run: %+v %s", job, e.closedThreads())
	}

	// Issue 13 only waits for a slot: the feature ends and its run is dropped.
	must(t, e.svc.Issue(ctx, "closed", 13))
	job, _ := e.st.JobByIssue(ctx, 13)
	if job.State != store.JobClosed || e.closedThreads() != "[thread3]" {
		t.Fatalf("job %+v closed %s", job, e.closedThreads())
	}
	if p := e.chat.last(); p.embed == nil || !strings.Contains(p.content, "Issue #13 was closed on GitHub") {
		t.Errorf("post %+v", p)
	}
	if w, _ := e.st.WaitingRuns(ctx); len(w) != 0 {
		t.Errorf("waiting %+v", w)
	}
	must(t, e.svc.Issue(ctx, "closed", 13)) // a repeat says nothing
	if e.postsContaining("was closed on GitHub") != 1 {
		t.Errorf("posts %+v", e.chat.posts)
	}

	must(t, e.svc.Issue(ctx, "reopened", 13))
	job, _ = e.st.JobByIssue(ctx, 13)
	if job.State != store.JobOpen || !strings.Contains(e.chat.last().content, "Issue #13 was reopened") {
		t.Errorf("job %+v post %+v", job, e.chat.last())
	}
}

func TestIssueClosedWithAPRIsLeftToThePR(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	job := e.withPR(t, "42", 12, "aaa")
	posts := len(e.chat.posts)
	must(t, e.svc.Issue(ctx, "closed", 11))
	job, _ = e.st.JobByID(ctx, job.ID)
	if job.State != store.JobOpen || len(e.chat.closed) != 0 || len(e.chat.posts) != posts {
		t.Errorf("job %+v closed %s posts %+v", job, e.closedThreads(), e.chat.posts[posts:])
	}
}
