package webhook

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/tfpp/the-game/bot/internal/core"
)

// ProgressHandler serves POST /bot/progress: live progress batches from
// harness/progress.sh, authenticated with the run's bearer token (core.ProgressToken).
//
//	204  applied (or ignored as a repeat)
//	400  malformed body
//	401  wrong token
//	410  the run is unknown, finished or has no thread: the sender stops
type ProgressHandler struct {
	Progress *core.Progress
	Logger   *slog.Logger
}

func (h *ProgressHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || token == "" {
		http.Error(w, "missing token", http.StatusUnauthorized)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 256<<10))
	if err != nil {
		http.Error(w, "body too large", http.StatusRequestEntityTooLarge)
		return
	}
	var u core.ProgressUpdate
	if err := json.Unmarshal(body, &u); err != nil || u.RequestID == "" {
		http.Error(w, "bad update", http.StatusBadRequest)
		return
	}
	switch err := h.Progress.Update(r.Context(), strings.TrimSpace(token), u); {
	case err == nil:
		w.WriteHeader(http.StatusNoContent)
	case errors.Is(err, core.ErrProgressDenied):
		http.Error(w, "invalid token", http.StatusUnauthorized)
	case errors.Is(err, core.ErrProgressClosed):
		http.Error(w, "run is not active", http.StatusGone)
	default:
		h.Logger.Error("progress", "err", err, "request", u.RequestID)
		http.Error(w, "internal error", http.StatusInternalServerError)
	}
}
