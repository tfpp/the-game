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

// maxChargeCents bounds a generic "charge" request (e.g. features/gun_machine's
// purchase price) well above any planned in-game cost, as a sanity check rather
// than a real security boundary — the game server is already fully trusted via
// the HMAC signature this handler requires.
const maxChargeCents = 100_00

// maxWagerCents bounds a slot machine's buy-in at $1,000,000,000, the same
// sanity-check role maxChargeCents plays for "charge".
const maxWagerCents = 100_000_000_000

// defaultWagerCents is the wager assumed when a request omits it, so older
// game servers keep charging the original $1-per-spin price.
const defaultWagerCents = 100

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
		AccountID   int64  `json:"account_id"`
		Action      string `json:"action"`
		ID          string `json:"id"`
		Timestamp   int64  `json:"timestamp"`
		AmountCents int64  `json:"amount_cents"`
		IncomeCents int64  `json:"income_cents"`
		WagerCents  int64  `json:"wager_cents"`
	}
	if json.Unmarshal(raw, &req) != nil || req.AccountID <= 0 || req.Timestamp < s.cfg.Now().Unix()-60 || req.Timestamp > s.cfg.Now().Unix()+60 {
		writeError(w, 400, "bad_request", "invalid request")
		return
	}
	if req.Action == "balance" {
		// Older game servers omit the rate; only the two model rates are accepted.
		if req.IncomeCents == 0 {
			req.IncomeCents = 500
		}
		if req.IncomeCents != 500 && req.IncomeCents != 425 {
			writeError(w, 400, "bad_request", "invalid income rate")
			return
		}
		balance, err := s.store.AccrueIncome(r.Context(), req.AccountID, s.cfg.Now().Unix(), req.IncomeCents)
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		writeJSON(w, 200, map[string]int64{"balance": balance})
		return
	}
	if req.Action == "credit" {
		if len(req.ID) != 64 {
			writeError(w, 400, "bad_request", "invalid credit")
			return
		}
		balance, err := s.store.CreditCoin(r.Context(), req.AccountID, req.ID)
		if errors.Is(err, store.ErrCreditConflict) {
			writeError(w, 409, "credit_conflict", "invalid credit")
			return
		}
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		writeJSON(w, 200, map[string]int64{"balance": balance})
		return
	}
	if req.Action == "charge" {
		if len(req.ID) != 64 || req.AmountCents <= 0 || req.AmountCents > maxChargeCents {
			writeError(w, 400, "bad_request", "invalid charge")
			return
		}
		balance, err := s.store.ChargeAccount(r.Context(), req.AccountID, req.ID, req.AmountCents)
		if errors.Is(err, store.ErrInsufficientMoney) {
			writeError(w, 409, "insufficient_money", "You can't afford that.")
			return
		}
		if errors.Is(err, store.ErrChargeConflict) {
			writeError(w, 409, "charge_conflict", "invalid charge")
			return
		}
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
	// Older game servers omit the wager; assume the original $1 machine.
	wagerCents := req.WagerCents
	if wagerCents == 0 {
		wagerCents = defaultWagerCents
	}
	if wagerCents < defaultWagerCents || wagerCents > maxWagerCents {
		writeError(w, 400, "bad_request", "invalid wager")
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
	result, err := s.store.PlaySlot(r.Context(), req.AccountID, req.ID, reels, wagerCents)
	if errors.Is(err, store.ErrInsufficientMoney) {
		writeError(w, 409, "insufficient_money", "You can't afford that spin.")
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
