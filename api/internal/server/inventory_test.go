package server

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGameInventorySavesAndLoads(t *testing.T) {
	h := newHarness(t)
	account, err := h.srv.store.CreateEmailAccount(context.Background(), "inv@example.com", "hash", "Ivy", h.now)
	if err != nil {
		t.Fatal(err)
	}
	request := func(domain string, payload string) *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/api/game/inventory", strings.NewReader(payload))
		mac := hmac.New(sha256.New, testKey)
		mac.Write([]byte(domain))
		mac.Write([]byte(payload))
		req.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		res := httptest.NewRecorder()
		h.h.ServeHTTP(res, req)
		return res
	}
	load := fmt.Sprintf(`{"account_id":%d,"action":"load","timestamp":%d}`, account.ID, h.now.Unix())
	if res := request("game-inventory-v1\n", load); res.Code != 200 || !strings.Contains(res.Body.String(), `"inventory":null`) {
		t.Fatal(res.Code, res.Body.String())
	}
	save := fmt.Sprintf(`{"account_id":%d,"action":"save","timestamp":%d,"inventory":{"hand":"burger"}}`, account.ID, h.now.Unix())
	if res := request("game-money-v1\n", save); res.Code != 401 {
		t.Fatal("money signature accepted", res.Code)
	}
	if res := request("game-inventory-v1\n", save); res.Code != 200 {
		t.Fatal(res.Code, res.Body.String())
	}
	res := request("game-inventory-v1\n", load)
	if res.Code != 200 || !strings.Contains(res.Body.String(), `"inventory":{"hand":"burger"}`) {
		t.Fatal(res.Body.String())
	}
	bad := fmt.Sprintf(`{"account_id":%d,"action":"save","timestamp":%d,"inventory":[1]}`, account.ID, h.now.Unix())
	if res := request("game-inventory-v1\n", bad); res.Code != 400 {
		t.Fatal(res.Code)
	}
	huge := fmt.Sprintf(`{"account_id":%d,"action":"save","timestamp":%d,"inventory":{"x":"%s"}}`, account.ID, h.now.Unix(), strings.Repeat("a", 9000))
	if res := request("game-inventory-v1\n", huge); res.Code != 400 {
		t.Fatal(res.Code)
	}
}
