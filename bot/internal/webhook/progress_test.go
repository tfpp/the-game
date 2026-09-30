package webhook

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tfpp/the-game/bot/internal/core"
	"github.com/tfpp/the-game/bot/internal/store"
)

type live struct{ posts chan string }

func (l live) PostLive(_ context.Context, thread string, e core.Embed) (string, error) {
	l.posts <- thread + " " + e.Description
	return "m1", nil
}

func (l live) EditLive(_ context.Context, thread, _ string, e core.Embed) error {
	l.posts <- thread + " " + e.Description
	return nil
}

func TestProgressHandler(t *testing.T) {
	ctx := context.Background()
	st, err := store.Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	now := time.Now()
	run, _ := st.Reserve(ctx, "42", 0, "implement", "", store.Limits{Window: time.Hour}, now)
	job, _ := st.CreateJob(ctx, store.Job{Issue: 7, Title: "t", ChannelID: "c", RequesterID: "42", RequesterName: "A"}, run.ID, now)
	st.SetThread(ctx, job.ID, "th", now)
	st.SetRunStatus(ctx, run.ID, store.RunInProgress, "", 0, "", now)

	log := slog.New(slog.DiscardHandler)
	svc := core.New(core.Config{Repo: "o/r", Workflow: "agent.yml", Logger: log}, st, noGitHub{}, chat{posts: make(chan string, 4)})
	l := live{posts: make(chan string, 4)}
	p := core.NewProgress(svc, l, []byte("s3cret"))
	h := &ProgressHandler{Progress: p, Logger: log}
	good := "Bearer " + core.ProgressToken([]byte("s3cret"), "bot-1")

	send := func(method, auth, body string) int {
		req := httptest.NewRequest(method, "/bot/progress", strings.NewReader(body))
		if auth != "" {
			req.Header.Set("Authorization", auth)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req)
		return w.Code
	}
	body := `{"request_id":"bot-1","agent":"pi","seq":1,"attempt":1,"attempts":1,"events":[{"kind":"tool","text":"ls"}]}`
	for _, c := range []struct {
		name, method, auth, body string
		want                     int
	}{
		{"GET", http.MethodGet, good, body, http.StatusMethodNotAllowed},
		{"no token", http.MethodPost, "", body, http.StatusUnauthorized},
		{"wrong token", http.MethodPost, "Bearer 00", body, http.StatusUnauthorized},
		{"bad JSON", http.MethodPost, good, "{", http.StatusBadRequest},
		{"no request", http.MethodPost, good, `{"events":[]}`, http.StatusBadRequest},
		{"too large", http.MethodPost, good, strings.Repeat(" ", 300<<10) + body, http.StatusRequestEntityTooLarge},
		{"ok", http.MethodPost, good, body, http.StatusNoContent},
	} {
		if got := send(c.method, c.auth, c.body); got != c.want {
			t.Errorf("%s: status %d, want %d", c.name, got, c.want)
		}
	}
	select {
	case got := <-l.posts:
		if got != "th 🔧 `ls`" {
			t.Errorf("posted %q", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("nothing posted")
	}
	p.Wait()

	st.SetRunStatus(ctx, run.ID, store.RunCompleted, "success", 0, "", now)
	if got := send(http.MethodPost, good, strings.Replace(body, `"seq":1`, `"seq":2`, 1)); got != http.StatusGone {
		t.Errorf("finished run: status %d, want 410", got)
	}
}
