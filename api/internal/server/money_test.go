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
	"time"

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

func TestGameMoneyGirlIncomeRate(t *testing.T) {
	h := newHarness(t)
	account, err := h.srv.store.CreateEmailAccount(context.Background(), "girl@example.com", "hash", "Girl", h.now)
	if err != nil {
		t.Fatal(err)
	}
	request := func(rate int64) *httptest.ResponseRecorder {
		body := []byte(fmt.Sprintf(`{"account_id":%d,"action":"balance","timestamp":%d,"income_cents":%d}`, account.ID, h.now.Unix(), rate))
		req := httptest.NewRequest("POST", "/api/game/money", bytes.NewReader(body))
		mac := hmac.New(sha256.New, testKey)
		mac.Write([]byte("game-money-v1\n"))
		mac.Write(body)
		req.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		res := httptest.NewRecorder()
		h.h.ServeHTTP(res, req)
		return res
	}
	if res := request(400); res.Code != 400 {
		t.Fatal(res.Body.String())
	}
	for i := 0; i <= 12; i++ {
		res := request(425)
		if res.Code != 200 {
			t.Fatal(res.Body.String())
		}
		if i == 12 && !strings.Contains(res.Body.String(), `"balance":2425`) {
			t.Fatal(res.Body.String())
		}
		h.now = h.now.Add(5 * time.Second)
	}
}

func TestGameMoneyChargeIsIdempotentAndRejectsInsufficientFunds(t *testing.T) {
	h := newHarness(t)
	account, err := h.srv.store.CreateEmailAccount(context.Background(), "charge@example.com", "hash", "Alice", h.now)
	if err != nil {
		t.Fatal(err)
	}
	request := func(payload []byte) *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/api/game/money", bytes.NewReader(payload))
		mac := hmac.New(sha256.New, testKey)
		mac.Write([]byte("game-money-v1\n"))
		mac.Write(payload)
		req.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		res := httptest.NewRecorder()
		h.h.ServeHTTP(res, req)
		return res
	}
	body := []byte(fmt.Sprintf(`{"account_id":%d,"action":"charge","id":"%s","timestamp":%d,"amount_cents":1500}`, account.ID, strings.Repeat("c", 64), h.now.Unix()))
	first := request(body)
	if first.Code != 200 {
		t.Fatal(first.Body.String())
	}
	var charge struct {
		Balance int64 `json:"balance"`
	}
	if err := json.Unmarshal(first.Body.Bytes(), &charge); err != nil {
		t.Fatal(err)
	}
	if charge.Balance != 500 {
		t.Fatal(charge.Balance)
	}
	second := request(body)
	if second.Body.String() != first.Body.String() {
		t.Fatalf("retry charged again: %s %s", first.Body, second.Body)
	}
	tooMuch := []byte(fmt.Sprintf(`{"account_id":%d,"action":"charge","id":"%s","timestamp":%d,"amount_cents":600}`, account.ID, strings.Repeat("d", 64), h.now.Unix()))
	if res := request(tooMuch); res.Code != 409 {
		t.Fatal(res.Code)
	}
	invalid := []byte(fmt.Sprintf(`{"account_id":%d,"action":"charge","id":"%s","timestamp":%d,"amount_cents":0}`, account.ID, strings.Repeat("e", 64), h.now.Unix()))
	if res := request(invalid); res.Code != 400 {
		t.Fatal(res.Code)
	}
}

func TestGameMoneyCreditIsIdempotent(t *testing.T) {
	h := newHarness(t)
	account, err := h.srv.store.CreateEmailAccount(context.Background(), "coin@example.com", "hash", "Alice", h.now)
	if err != nil {
		t.Fatal(err)
	}
	body := []byte(fmt.Sprintf(`{"account_id":%d,"action":"credit","id":"%s","timestamp":%d}`, account.ID, strings.Repeat("b", 64), h.now.Unix()))
	request := func(payload []byte) *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/api/game/money", bytes.NewReader(payload))
		mac := hmac.New(sha256.New, testKey)
		mac.Write([]byte("game-money-v1\n"))
		mac.Write(payload)
		req.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		res := httptest.NewRecorder()
		h.h.ServeHTTP(res, req)
		return res
	}
	first := request(body)
	if first.Code != 200 {
		t.Fatal(first.Body.String())
	}
	var credit struct {
		Balance int64 `json:"balance"`
	}
	if err := json.Unmarshal(first.Body.Bytes(), &credit); err != nil {
		t.Fatal(err)
	}
	if credit.Balance != 3000 {
		t.Fatal(credit.Balance)
	}
	second := request(body)
	if second.Body.String() != first.Body.String() {
		t.Fatalf("retry paid again: %s %s", first.Body, second.Body)
	}
}
