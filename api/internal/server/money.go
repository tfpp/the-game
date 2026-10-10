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
const maxLootSaleCents = 100_000_00

// maxWagerCents bounds a slot machine's buy-in at $1,000,000,000, the same
// sanity-check role maxChargeCents plays for "charge".
const maxWagerCents = 100_000_000_000

// maxRoulettePayoutMultiple bounds a roulette payout: a straight-up win
// returns 35 to 1 plus the stake, 36 times the whole wager at most.
const maxRoulettePayoutMultiple = 36

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
		AccountID   int64           `json:"account_id"`
		Action      string          `json:"action"`
		ID          string          `json:"id"`
		Timestamp   int64           `json:"timestamp"`
		AmountCents int64           `json:"amount_cents"`
		IncomeCents int64           `json:"income_cents"`
		WagerCents  int64           `json:"wager_cents"`
		PayoutCents int64           `json:"payout_cents"`
		Blessings   int             `json:"blessings"`
		Revision    int64           `json:"revision"`
		Delta       int64           `json:"delta"`
		Document    json.RawMessage `json:"document"`
	}
	if json.Unmarshal(raw, &req) != nil || req.AccountID <= 0 || req.Timestamp < s.cfg.Now().Unix()-60 || req.Timestamp > s.cfg.Now().Unix()+60 {
		writeError(w, 400, "bad_request", "invalid request")
		return
	}
	if req.Action == "cosmetics_load" {
		result, err := s.store.Cosmetics(r.Context(), req.AccountID)
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		writeJSON(w, 200, result)
		return
	}
	if req.Action == "cosmetics" {
		var document map[string]map[string]any
		if len(req.ID) != 64 || req.Revision < 0 || req.Revision > 1_000_000_000 ||
			req.Delta < -maxChargeCents || req.Delta > maxLootSaleCents ||
			len(req.Document) > maxInventoryBytes || json.Unmarshal(req.Document, &document) != nil ||
			len(document) != 3 || document["crates"] == nil || document["skins"] == nil || document["equipped"] == nil {
			writeError(w, 400, "bad_request", "invalid cosmetic transaction")
			return
		}
		result, err := s.store.CommitCosmetics(r.Context(), req.AccountID, req.ID, req.Revision, req.Delta, string(req.Document))
		if errors.Is(err, store.ErrInsufficientMoney) {
			writeError(w, 409, "insufficient_money", "You can't afford that crate.")
			return
		}
		if errors.Is(err, store.ErrCosmeticConflict) {
			writeError(w, 409, "cosmetic_conflict", "Collection changed; refresh and try again.")
			return
		}
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		writeJSON(w, 200, result)
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
		seconds, err := s.store.Playtime(r.Context(), req.AccountID)
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		writeJSON(w, 200, map[string]int64{"balance": balance, "playtime_seconds": seconds})
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
	if req.Action == "sell" {
		if len(req.ID) != 64 || req.AmountCents <= 0 || req.AmountCents > maxLootSaleCents {
			writeError(w, 400, "bad_request", "invalid sale")
			return
		}
		balance, err := s.store.CreditLoot(r.Context(), req.AccountID, req.ID, req.AmountCents)
		if errors.Is(err, store.ErrLootSaleConflict) {
			writeError(w, 409, "sale_conflict", "invalid sale")
			return
		}
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		writeJSON(w, 200, map[string]int64{"balance": balance})
		return
	}
	if req.Action == "roulette" {
		if len(req.ID) != 64 || req.WagerCents <= 0 || req.WagerCents > maxWagerCents || req.PayoutCents < 0 || req.PayoutCents > req.WagerCents*maxRoulettePayoutMultiple {
			writeError(w, 400, "bad_request", "invalid roulette bet")
			return
		}
		balance, err := s.store.SettleRoulette(r.Context(), req.AccountID, req.ID, req.WagerCents, req.PayoutCents)
		if errors.Is(err, store.ErrInsufficientMoney) {
			writeError(w, 409, "insufficient_money", "You can't cover that bet.")
			return
		}
		if errors.Is(err, store.ErrRouletteConflict) {
			writeError(w, 409, "roulette_conflict", "invalid roulette bet")
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
	if req.Blessings < 0 || req.Blessings > 5 {
		writeError(w, 400, "bad_request", "invalid blessings")
		return
	}
	n, err := rand.Int(rand.Reader, big.NewInt(125))
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	reels := slotReels(int(n.Int64()), req.Blessings)
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

// slotReels matches SlotSpinCycle.result_for_ticket in the game. Each blessing
// adds 200% of the 4% base win chance; all five winning symbols stay equiprobable.
func slotReels(ticket, blessings int) [3]int {
	if ticket < 5+10*blessings {
		symbol := ticket % 5
		return [3]int{symbol, symbol, symbol}
	}
	losing := ticket - 5
	index := losing + 1 + losing/30
	return [3]int{index / 25, (index / 5) % 5, index % 5}
}
