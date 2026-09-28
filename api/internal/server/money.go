package server

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"

	"github.com/tfpp/the-game/api/internal/store"
)

// Only the dedicated server possesses the ticket key. Domain separation prevents
// join-ticket signatures from being used to authorize wallet operations.
func (s *Server) gameMoney(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		writeError(w, 400, "bad_request", "invalid body")
		return
	}
	mac := hmac.New(sha256.New, s.cfg.TicketKey)
	mac.Write([]byte("game-money-v1\n"))
	mac.Write(raw)
	signature, err := hex.DecodeString(r.Header.Get("X-Game-Signature"))
	if err != nil || len(s.cfg.TicketKey) == 0 || !hmac.Equal(signature, mac.Sum(nil)) {
		writeError(w, 401, "unauthorized", "game server authentication required")
		return
	}
	var req struct {
		AccountID int64  `json:"account_id"`
		Action    string `json:"action"`
		ID        string `json:"id"`
		Timestamp int64  `json:"timestamp"`
	}
	if json.Unmarshal(raw, &req) != nil || req.AccountID <= 0 || req.Timestamp < s.cfg.Now().Unix()-60 || req.Timestamp > s.cfg.Now().Unix()+60 {
		writeError(w, 400, "bad_request", "invalid request")
		return
	}
	if req.Action == "balance" {
		balance, err := s.store.AccrueIncome(r.Context(), req.AccountID, s.cfg.Now().Unix())
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		writeJSON(w, 200, map[string]int64{"balance": balance})
		return
	}
	if req.Action != "spin" || len(req.ID) != 64 {
		writeError(w, 400, "bad_request", "invalid spin")
		return
	}
	var reels [3]int
	for i := range reels {
		n, err := rand.Int(rand.Reader, big.NewInt(5))
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		reels[i] = int(n.Int64())
	}
	result, err := s.store.PlaySlot(r.Context(), req.AccountID, req.ID, reels)
	if errors.Is(err, store.ErrInsufficientMoney) {
		writeError(w, 409, "insufficient_money", "You need $1 to spin.")
		return
	}
	if errors.Is(err, store.ErrSpinConflict) {
		writeError(w, 409, "spin_conflict", "invalid spin")
		return
	}
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, 200, result)
}
