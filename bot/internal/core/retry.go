package core

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/tfpp/the-game/bot/internal/store"
)

const retryPrefix = "retry:"

// RetryButtonID is the custom ID of the Retry button for a failed run.
func RetryButtonID(runID int64) string { return retryPrefix + strconv.FormatInt(runID, 10) }

// IsRetryButton reports whether a button's custom ID is a Retry button.
func IsRetryButton(id string) bool { return strings.HasPrefix(id, retryPrefix) }

// retryable reports whether a run's mode can be started again from Discord. Conflict
// resolution is automatic and retries itself on the next conflict check.
func retryable(mode string) bool { return mode == "implement" || mode == "revise" }

// RetryRequest is a Retry button press in a feature thread.
type RetryRequest struct {
	UserID   string
	UserName string
	HasRole  bool // the requester role
	ThreadID string
	ButtonID string
}

// postFailure tells the thread that run ended without a change, with a Retry button when
// the run can be retried.
func (s *Service) postFailure(ctx context.Context, job store.Job, run store.Run, content string, ping ...string) {
	if job.ThreadID == "" {
		return
	}
	if !retryable(run.Mode) {
		s.post(ctx, job, content, ping...)
		return
	}
	if err := s.chat.PostButton(ctx, job.ThreadID, content, "Retry", RetryButtonID(run.ID), ping...); err != nil {
		s.log.Error("post to thread", "err", err, "issue", job.Issue)
	}
}

// Retry starts a failed implement or revise run again with the same instructions. Only
// the newest run of a feature can be retried, and only while nothing else is running.
func (s *Service) Retry(ctx context.Context, req RetryRequest, r Responder) error {
	id, err := strconv.ParseInt(strings.TrimPrefix(req.ButtonID, retryPrefix), 10, 64)
	if err != nil || !IsRetryButton(req.ButtonID) {
		return r.Reject(ctx, "That button isn't a retry button.")
	}
	job, err := s.st.JobByThread(ctx, req.ThreadID)
	if errors.Is(err, store.ErrNotFound) {
		return r.Reject(ctx, "That button only works inside a feature's thread.")
	} else if err != nil {
		return err
	}
	old, err := s.st.RunByID(ctx, id)
	if errors.Is(err, store.ErrNotFound) || (err == nil && old.JobID != job.ID) {
		return r.Reject(ctx, "That button belongs to another feature.")
	} else if err != nil {
		return err
	}
	switch {
	case !req.HasRole && req.UserID != job.RequesterID:
		return r.Reject(ctx, "Only the requester or someone with the requester role can retry this.")
	case job.State != store.JobOpen:
		return r.Reject(ctx, "This feature is "+job.State+", so it can't be retried.")
	case !retryable(old.Mode):
		return r.Reject(ctx, "This run can't be retried from Discord.")
	case old.Mode == "implement" && job.PR != 0:
		return r.Reject(ctx, fmt.Sprintf("PR #%d is already open. Use `/revise` to ask for changes.", job.PR))
	case old.Mode == "revise" && job.PR == 0:
		return r.Reject(ctx, "There's no PR to revise.")
	}

	// Check and reserve under the lock, so two presses can't both start a run.
	s.mu.Lock()
	run, problem, err := s.reserveRetry(ctx, req.UserID, job, old)
	s.mu.Unlock()
	if err != nil {
		return s.rejectLimit(ctx, r, err)
	}
	if problem != "" {
		return r.Reject(ctx, problem)
	}
	if err := r.Defer(ctx); err != nil {
		s.failRun(ctx, run.ID)
		return err
	}
	what := "the agent run"
	number := job.Issue
	if old.Mode == "revise" {
		what = fmt.Sprintf("the changes to PR #%d", job.PR)
		number = job.PR
	}
	if run.Status == store.RunWaiting {
		err := r.Respond(ctx, fmt.Sprintf("🔁 <@%s> is retrying %s. The agent is busy, so this is %s.",
			req.UserID, what, s.linePosition(ctx, run.ID)))
		s.drain(ctx)
		return err
	}
	if err := s.dispatch(ctx, run, number, old.Instructions); err != nil {
		return r.Respond(ctx, "❌ I couldn't start the agent. Try again later.")
	}
	return r.Respond(ctx, fmt.Sprintf("🔁 <@%s> is retrying %s. The agent is queued; I'll post progress here.",
		req.UserID, what))
}

// reserveRetry reserves a copy of old, or explains why it can't be retried. Hold s.mu.
func (s *Service) reserveRetry(ctx context.Context, userID string, job store.Job, old store.Run) (store.Run, string, error) {
	if active, err := s.st.ActiveRunForJob(ctx, job.ID); err == nil {
		if active.ID == old.ID {
			return store.Run{}, "That run is still wrapping up. Try again in a minute.", nil
		}
		return store.Run{}, "The agent is already working on this or waiting to. Wait for it to finish.", nil
	} else if !errors.Is(err, store.ErrNotFound) {
		return store.Run{}, "", err
	}
	latest, err := s.st.LatestRunForJob(ctx, job.ID)
	if err != nil {
		return store.Run{}, "", err
	}
	if latest.ID != old.ID {
		return store.Run{}, "The agent has run again since then, so this button is out of date.", nil
	}
	run, err := s.st.Reserve(ctx, userID, job.ID, old.Mode, old.Instructions, s.cfg.Limits, s.cfg.Now())
	return run, "", err
}
