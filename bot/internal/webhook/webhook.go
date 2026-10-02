// Package webhook receives the GitHub App's webhooks: it checks signatures, drops
// repeated deliveries and hands events to core, one at a time and in arrival order.
package webhook

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/tfpp/the-game/bot/internal/core"
	"github.com/tfpp/the-game/bot/internal/github"
	"github.com/tfpp/the-game/bot/internal/store"
)

type delivery struct {
	id, event string
	body      []byte
}

// Handler serves POST requests from GitHub.
type Handler struct {
	Secret  []byte
	Repo    string // events from other repositories are ignored
	Service *core.Service
	Store   *store.Store
	Logger  *slog.Logger

	queue chan delivery
}

// Start runs the worker that processes deliveries until ctx ends.
func (h *Handler) Start(ctx context.Context) {
	h.queue = make(chan delivery, 256)
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case d := <-h.queue:
				dctx, cancel := context.WithTimeout(ctx, time.Minute)
				if err := h.handle(dctx, d); err != nil {
					h.Logger.Error("webhook", "event", d.event, "delivery", d.id, "err", err)
				}
				cancel()
			}
		}
	}()
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 5<<20))
	if err != nil {
		http.Error(w, "body too large", http.StatusRequestEntityTooLarge)
		return
	}
	if !github.ValidSignature(h.Secret, body, r.Header.Get("X-Hub-Signature-256")) {
		http.Error(w, "bad signature", http.StatusUnauthorized)
		return
	}
	d := delivery{id: r.Header.Get("X-GitHub-Delivery"), event: r.Header.Get("X-GitHub-Event"), body: body}
	select {
	case h.queue <- d:
		w.WriteHeader(http.StatusAccepted)
	default:
		http.Error(w, "busy", http.StatusServiceUnavailable)
	}
}

func (h *Handler) handle(ctx context.Context, d delivery) error {
	if d.id != "" {
		fresh, err := h.Store.MarkSeen(ctx, "delivery:"+d.id, time.Now())
		if err != nil || !fresh {
			return err
		}
	}
	var repo struct {
		Repository github.Repository `json:"repository"`
	}
	if err := json.Unmarshal(d.body, &repo); err != nil {
		return err
	}
	if !strings.EqualFold(repo.Repository.FullName, h.Repo) {
		return nil
	}
	switch d.event {
	case "issue_comment":
		var ev github.IssueCommentEvent
		if err := json.Unmarshal(d.body, &ev); err != nil {
			return err
		}
		if ev.Action != "created" {
			return nil
		}
		return h.Service.Comment(ctx, ev.Issue.Number, ev.Comment)
	case "issues":
		var ev github.IssuesEvent
		if err := json.Unmarshal(d.body, &ev); err != nil {
			return err
		}
		return h.Service.Issue(ctx, ev.Action, ev.Issue.Number)
	case "pull_request":
		var ev github.PullRequestEvent
		if err := json.Unmarshal(d.body, &ev); err != nil {
			return err
		}
		return h.Service.PullRequest(ctx, ev)
	case "workflow_run":
		var ev github.WorkflowRunEvent
		if err := json.Unmarshal(d.body, &ev); err != nil {
			return err
		}
		return h.Service.WorkflowRun(ctx, ev.WorkflowRun)
	}
	return nil
}
