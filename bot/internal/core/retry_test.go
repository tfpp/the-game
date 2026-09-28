package core

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/tfpp/the-game/bot/internal/github"
	"github.com/tfpp/the-game/bot/internal/store"
)

func (e *env) retry(t *testing.T, user string, role bool, thread, button string) *fakeResponder {
	t.Helper()
	r := &fakeResponder{}
	must(t, e.svc.Retry(context.Background(), RetryRequest{
		UserID: user, UserName: "Bob", HasRole: role, ThreadID: thread, ButtonID: button,
	}, r))
	return r
}

func agentDone(issue int, runID, conclusion string) github.WorkflowRun {
	return github.WorkflowRun{ID: 1, Path: ".github/workflows/agent.yml", HTMLURL: "https://run",
		DisplayTitle: fmt.Sprintf("agent #%d implement [bot-%s]", issue, runID), Status: "completed", Conclusion: conclusion}
}

func TestCancelledImplementRunCanBeRetried(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please", "codex")
	must(t, e.svc.WorkflowRun(ctx, agentDone(11, "1", "cancelled")))
	p := e.chat.last()
	if p.button != "retry:1" || p.ping != "42" || !strings.Contains(p.content, "`cancelled`") {
		t.Fatalf("failure post %+v", p)
	}
	if r := e.retry(t, "7", false, "thread1", p.button); !strings.Contains(r.rejected, "Only the requester") {
		t.Errorf("stranger: %+v", r)
	}
	if r := e.retry(t, "42", false, "elsewhere", p.button); !strings.Contains(r.rejected, "feature's thread") {
		t.Errorf("outside thread: %+v", r)
	}
	r := e.retry(t, "42", false, "thread1", p.button)
	if r.rejected != "" || !strings.Contains(r.response, "<@42> is retrying the agent run. The agent is queued") {
		t.Fatalf("retry: %+v", r)
	}
	d := e.gh.dispatches[len(e.gh.dispatches)-1]
	if len(e.gh.dispatches) != 2 || d["number"] != "11" || d["mode"] != "implement" || d["agent"] != "codex" || d["request_id"] != "bot-2" {
		t.Errorf("dispatches %v", e.gh.dispatches)
	}
	if r := e.retry(t, "42", false, "thread1", p.button); !strings.Contains(r.rejected, "already working") {
		t.Errorf("double press: %+v", r)
	}
	// Once the retry has finished too, the first button is out of date.
	must(t, e.svc.WorkflowRun(ctx, agentDone(11, "2", "failure")))
	if p := e.chat.last(); p.button != "retry:2" {
		t.Errorf("second failure post %+v", p)
	}
	if r := e.retry(t, "42", false, "thread1", "retry:1"); !strings.Contains(r.rejected, "out of date") {
		t.Errorf("stale button: %+v", r)
	}
	// The newest button is live, within the per-user limit (two runs in this env).
	if r := e.retry(t, "42", false, "thread1", "retry:2"); !strings.Contains(r.rejected, "your 2 agent runs") {
		t.Errorf("newest button: %+v", r)
	}
	if r := e.retry(t, "8", true, "thread1", "retry:2"); r.rejected != "" || len(e.gh.dispatches) != 3 {
		t.Errorf("newest button: %+v", r)
	}
}

func TestHarnessFailureOnARevisionCanBeRetried(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	job, _ := e.st.JobByIssue(ctx, 11)
	must(t, e.st.SetPR(ctx, job.ID, 12, e.now))
	must(t, e.svc.WorkflowRun(ctx, agentDone(11, "1", "success")))
	rv := &fakeResponder{}
	must(t, e.svc.Revise(ctx, ReviseRequest{UserID: "42", UserName: "Bob", HasRole: true, ThreadID: "thread1", Text: "make them red"}, rv))

	bot := github.User{Login: "the-game[bot]", Type: "Bot"}
	body := "🤖 `claude` (`revise`) did not produce a change: the work did not pass harness checks after 3 attempt(s) ([run](https://run) · Model(s): m · Tokens used: 1 · Estimated cost (USD API-equivalent): $0.01)\n<details>log</details>"
	must(t, e.svc.Comment(ctx, 12, github.Comment{ID: 5, User: bot, Body: body, HTMLURL: "https://c"}))
	p := e.chat.last()
	if p.button != "retry:2" || p.ping != "42" || !strings.Contains(p.content, "did not produce a change") || !strings.Contains(p.content, "[Logs on GitHub]") {
		t.Fatalf("failure post %+v", p)
	}
	// The harness comments before the workflow run finishes.
	if r := e.retry(t, "42", false, "thread1", p.button); !strings.Contains(r.rejected, "still wrapping up") {
		t.Errorf("early press: %+v", r)
	}
	must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{ID: 2, Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #12 revise [bot-2]", Status: "completed", Conclusion: "failure"}))
	if p := e.chat.last(); p.button != "retry:2" {
		t.Errorf("relayed run should not post again: %+v", e.chat.posts)
	}
	r := e.retry(t, "7", true, "thread1", "retry:2")
	if r.rejected != "" || !strings.Contains(r.response, "retrying the changes to PR #12") {
		t.Fatalf("retry: %+v", r)
	}
	d := e.gh.dispatches[len(e.gh.dispatches)-1]
	if d["number"] != "12" || d["mode"] != "revise" || d["instructions"] != "From Bob on Discord:\n\nmake them red" || d["request_id"] != "bot-3" {
		t.Errorf("dispatch %v", d)
	}
	if run := e.runStatus(t, 3); run.UserID != "7" || run.Status != store.RunDispatched {
		t.Errorf("retry run %+v", run)
	}
}

func TestRetryChecks(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	must(t, e.svc.WorkflowRun(ctx, agentDone(11, "1", "cancelled")))
	job, _ := e.st.JobByIssue(ctx, 11)

	must(t, e.st.SetPR(ctx, job.ID, 12, e.now))
	if r := e.retry(t, "42", false, "thread1", "retry:1"); !strings.Contains(r.rejected, "PR #12 is already open") {
		t.Errorf("implement with PR: %+v", r)
	}
	must(t, e.st.SetJobState(ctx, job.ID, store.JobClosed, e.now))
	if r := e.retry(t, "42", false, "thread1", "retry:1"); !strings.Contains(r.rejected, "closed") {
		t.Errorf("closed: %+v", r)
	}
	for _, id := range []string{"retry:x", "retry:99"} {
		if r := e.retry(t, "42", false, "thread1", id); r.rejected == "" {
			t.Errorf("%s accepted: %+v", id, r)
		}
	}
	// The per-user limit applies to retries too.
	e2 := newEnv(t)
	e2.feature(t, "42", "add jump pads please")
	e2.feature(t, "42", "add a scoreboard")
	must(t, e2.svc.WorkflowRun(ctx, agentDone(11, "1", "cancelled")))
	if r := e2.retry(t, "42", false, "thread1", "retry:1"); !strings.Contains(r.rejected, "your 2 agent runs") {
		t.Errorf("limit: %+v", r)
	}
}

func TestRunThatNeverStartedCanBeRetried(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	e.now = e.now.Add(20 * time.Minute)
	must(t, e.svc.Reconcile(ctx))
	p := e.chat.last()
	if p.button != "retry:1" || !strings.Contains(p.content, "never started") || p.ping != "42" {
		t.Fatalf("post %+v", p)
	}
	if r := e.retry(t, "42", false, "thread1", p.button); r.rejected != "" || len(e.gh.dispatches) != 2 {
		t.Errorf("retry %+v dispatches %v", r, e.gh.dispatches)
	}
}
