package server

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tfpp/the-game/api/internal/store"
)

func TestGameMoneyRequiresServerAndRetriesSafely(t *testing.T) {
	h := newHarness(t)
	account, err := h.srv.store.CreateEmailAccount(context.Background(), "money@example.com", "hash", "Alice", h.now)
	if err != nil {
		t.Fatal(err)
	}
	body := []byte(fmt.Sprintf(`{"account_id":%d,"action":"spin","id":"%s","timestamp":%d}`, account.ID, strings.Repeat("a", 64), h.now.Unix()))
	request := func(key []byte, payload []byte) *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/api/game/money", bytes.NewReader(payload))
		mac := hmac.New(sha256.New, key)
		mac.Write([]byte("game-money-v1\n"))
		mac.Write(payload)
		req.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		res := httptest.NewRecorder()
		h.h.ServeHTTP(res, req)
		return res
	}
	if res := request([]byte("client-session"), body); res.Code != 401 {
		t.Fatal(res.Code)
	}
	first := request(testKey, body)
	if first.Code != 200 {
		t.Fatal(first.Body.String())
	}
	var spin store.Spin
	if err := json.Unmarshal(first.Body.Bytes(), &spin); err != nil {
		t.Fatal(err)
	}
	if spin.Balance != 1900+spin.Payout || spin.Payout != store.SlotPayout(spin.Reels) {
		t.Fatal(spin)
	}
	second := request(testKey, body)
	if second.Body.String() != first.Body.String() {
		t.Fatalf("retry changed result: %s %s", first.Body, second.Body)
	}
	stale := bytes.Replace(body, []byte(fmt.Sprint(h.now.Unix())), []byte(fmt.Sprint(h.now.Unix()-61)), 1)
	if res := request(testKey, stale); res.Code != 400 {
		t.Fatal(res.Code)
	}
}
