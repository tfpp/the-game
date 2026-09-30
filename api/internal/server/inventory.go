package server

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
)

// maxInventoryBytes bounds one saved inventory document. Eleven slots plus keys
// of short item IDs need far less.
const maxInventoryBytes = 8 << 10

// gameInventory loads and saves a player's inventory for the dedicated game
// server. Like gameMoney, only the ticket-key holder can call it, under its own
// signature domain so money signatures can't be replayed here.
func (s *Server) gameInventory(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	if err != nil {
		writeError(w, 400, "bad_request", "invalid body")
		return
	}
	mac := hmac.New(sha256.New, s.cfg.TicketKey)
	mac.Write([]byte("game-inventory-v1\n"))
	mac.Write(raw)
	signature, err := hex.DecodeString(r.Header.Get("X-Game-Signature"))
	if err != nil || len(s.cfg.TicketKey) == 0 || !hmac.Equal(signature, mac.Sum(nil)) {
		writeError(w, 401, "unauthorized", "game server authentication required")
		return
	}
	var req struct {
		AccountID int64           `json:"account_id"`
		Action    string          `json:"action"`
		Timestamp int64           `json:"timestamp"`
		Inventory json.RawMessage `json:"inventory"`
	}
	now := s.cfg.Now().Unix()
	if json.Unmarshal(raw, &req) != nil || req.AccountID <= 0 || req.Timestamp < now-60 || req.Timestamp > now+60 {
		writeError(w, 400, "bad_request", "invalid request")
		return
	}
	switch req.Action {
	case "load":
		items, err := s.store.Inventory(r.Context(), req.AccountID)
		if err != nil {
			s.internalError(w, r, err)
			return
		}
		inventory := json.RawMessage("null")
		if items != "" {
			inventory = json.RawMessage(items)
		}
		writeJSON(w, 200, map[string]json.RawMessage{"inventory": inventory})
	case "save":
		var document map[string]any
		if len(req.Inventory) > maxInventoryBytes || json.Unmarshal(req.Inventory, &document) != nil || document == nil {
			writeError(w, 400, "bad_request", "invalid inventory")
			return
		}
		if err := s.store.SaveInventory(r.Context(), req.AccountID, string(req.Inventory), now); err != nil {
			s.internalError(w, r, err)
			return
		}
		writeJSON(w, 200, map[string]bool{"saved": true})
	default:
		writeError(w, 400, "bad_request", "invalid action")
	}
}
