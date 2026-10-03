package server

import (
	"crypto/subtle"
	"errors"
	"net/http"
	"regexp"

	"github.com/tfpp/the-game/api/internal/store"
)

var discordProfileID = regexp.MustCompile(`^[1-9][0-9]{0,19}$`)

// Only the configured bot can query profiles. This credential cannot modify accounts
// or authorize gameplay operations; responses contain only game-facing information.
func (s *Server) botProfile(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if len(s.cfg.ProfileKey) < 32 ||
		subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), []byte("Bearer "+string(s.cfg.ProfileKey))) != 1 {
		writeError(w, 401, "unauthorized", "bot authentication required")
		return
	}
	if !s.limit(w, "profile-bot", "bot") {
		return
	}
	user := r.PathValue("user")
	if !discordProfileID.MatchString(user) {
		writeError(w, 400, "bad_request", "invalid user")
		return
	}
	p, err := s.store.ProfileByDiscord(r.Context(), user)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, 404, "not_found", "no linked game profile")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, 200, p)
}
