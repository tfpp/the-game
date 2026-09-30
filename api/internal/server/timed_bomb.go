package server

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"

	"github.com/tfpp/the-game/api/internal/store"
)

func (s *Server) gameTimedBomb(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1024))
	if err != nil {
		writeError(w, 400, "bad_request", "invalid body")
		return
	}
	mac := hmac.New(sha256.New, s.cfg.TicketKey)
	mac.Write([]byte("game-timed-bomb-v1\n"))
	mac.Write(raw)
	signature, err := hex.DecodeString(r.Header.Get("X-Game-Signature"))
	if err != nil || len(s.cfg.TicketKey) == 0 || !hmac.Equal(signature, mac.Sum(nil)) {
		writeError(w, 401, "unauthorized", "game server authentication required")
		return
	}
	var req struct {
		Action    string `json:"action"`
		Code      string `json:"code"`
		Timestamp int64  `json:"timestamp"`
	}
	now := s.cfg.Now().Unix()
	if json.Unmarshal(raw, &req) != nil || req.Timestamp < now-60 || req.Timestamp > now+60 ||
		(req.Action != "status" && req.Action != "defuse") ||
		(req.Action == "defuse" && !store.ValidBombCode(req.Code)) ||
		(req.Action == "status" && req.Code != "") {
		writeError(w, 400, "bad_request", "invalid request")
		return
	}
	snapshot, err := s.store.TimedBomb(r.Context(), now, req.Code)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, 200, snapshot)
}
