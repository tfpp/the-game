package webhook

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tfpp/the-game/bot/internal/core"
	"github.com/tfpp/the-game/bot/internal/store"
)

type noGitHub struct{ core.GitHub }

type chat struct{ posts chan string }

func (c chat) Post(_ context.Context, _, content string, _ ...string) error {
	c.posts <- content
	return nil
}

func (c chat) PostEmbed(_ context.Context, _, content string, e core.Embed, _ *core.Button, _ ...string) error {
	c.posts <- content + " " + e.Title + " " + e.Description
	return nil
}

func (c chat) CloseThread(context.Context, string) error { return nil }

func sign(secret, body string) string {
	m := hmac.New(sha256.New, []byte(secret))
	m.Write([]byte(body))
	return "sha256=" + hex.EncodeToString(m.Sum(nil))
}

func TestHandler(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	st, err := store.Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	now := time.Now()
	run, _ := st.Reserve(ctx, "42", 0, "implement", "", store.Limits{Window: time.Hour}, now)
	job, _ := st.CreateJob(ctx, store.Job{Issue: 7, Title: "t", ChannelID: "c", RequesterID: "42", RequesterName: "A"}, run.ID, now)
	st.SetThread(ctx, job.ID, "th", now)

	c := chat{posts: make(chan string, 4)}
	log := slog.New(slog.DiscardHandler)
	svc := core.New(core.Config{Repo: "o/r", Workflow: "agent.yml", CIWorkflow: "game-ci.yml", Logger: log}, st, noGitHub{}, c)
	h := &Handler{Secret: []byte("s3cret"), Repo: "o/r", Service: svc, Store: st, Logger: log}
	h.Start(ctx)

	send := func(event, body, sig, delivery string) int {
		req := httptest.NewRequest(http.MethodPost, "/bot/github", strings.NewReader(body))
		req.Header.Set("X-GitHub-Event", event)
		req.Header.Set("X-GitHub-Delivery", delivery)
		req.Header.Set("X-Hub-Signature-256", sig)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req)
		return w.Code
	}
	comment := func(id, repo string) string {
		return `{"action":"created","issue":{"number":7},"repository":{"full_name":"` + repo + `"},
			"comment":{"id":` + id + `,"body":"🤖 Opened https://github.com/o/r/pull/8","user":{"login":"x[bot]","type":"Bot"}}}`
	}

	if code := send("issue_comment", comment("1", "o/r"), sign("wrong", comment("1", "o/r")), "d1"); code != http.StatusUnauthorized {
		t.Fatalf("bad signature: %d", code)
	}
	body := comment("1", "o/r")
	if code := send("issue_comment", body, sign("s3cret", body), "d1"); code != http.StatusAccepted {
		t.Fatalf("good signature: %d", code)
	}
	select {
	case p := <-c.posts:
		if !strings.Contains(p, "PR #8 opened") {
			t.Errorf("post %q", p)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("comment not relayed")
	}
	// A redelivery, and an event from another repository, are ignored.
	send("issue_comment", body, sign("s3cret", body), "d1")
	other := comment("2", "someone/else")
	send("issue_comment", other, sign("s3cret", other), "d2")
	select {
	case p := <-c.posts:
		t.Errorf("unexpected post %q", p)
	case <-time.After(200 * time.Millisecond):
	}
	if j, _ := st.JobByIssue(ctx, 7); j.PR != 8 {
		t.Errorf("PR not recorded: %+v", j)
	}
}
