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

func TestCosmeticsAuthenticatedAtomicEndpoint(t *testing.T) {
	h := newHarness(t)
	account, err := h.srv.store.CreateEmailAccount(context.Background(), "skin@example.com", "hash", "Prawn", h.now)
	if err != nil {
		t.Fatal(err)
	}
	request := func(domain, payload string) *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/api/game/money", strings.NewReader(payload))
		mac := hmac.New(sha256.New, testKey)
		mac.Write([]byte(domain))
		mac.Write([]byte(payload))
		req.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		res := httptest.NewRecorder()
		h.h.ServeHTTP(res, req)
		return res
	}
	load := fmt.Sprintf(`{"account_id":%d,"action":"cosmetics_load","timestamp":%d}`, account.ID, h.now.Unix())
	if res := request("game-inventory-v1\n", load); res.Code != 401 {
		t.Fatal("wrong domain accepted", res.Code)
	}
	if res := request("game-money-v1\n", load); res.Code != 200 || !strings.Contains(res.Body.String(), `"revision":0`) {
		t.Fatal(res.Code, res.Body.String())
	}
	purchase := fmt.Sprintf(`{"account_id":%d,"action":"cosmetics","timestamp":%d,"id":"%s","revision":0,"delta":-500,"document":{"crates":{"harbour":1},"skins":{},"equipped":{}}}`, account.ID, h.now.Unix(), strings.Repeat("a", 64))
	for i := 0; i < 2; i++ {
		res := request("game-money-v1\n", purchase)
		if res.Code != 200 || !strings.Contains(res.Body.String(), `"balance":1500`) || !strings.Contains(res.Body.String(), `"revision":1`) {
			t.Fatal(res.Code, res.Body.String())
		}
	}
	for _, invalid := range []string{
		strings.Replace(purchase, `"delta":-500`, `"delta":-10001`, 1),
		strings.Replace(purchase, `"revision":0`, `"revision":-1`, 1),
		strings.Replace(purchase, `"equipped":{}`, `"equipped":[]`, 1),
		strings.Replace(purchase, `"equipped":{}`, `"extra":{}`, 1),
		strings.Replace(purchase, `"skins":{}`, `"skins":{"huge":"`+strings.Repeat("a", 9000)+`"}`, 1),
		strings.Replace(purchase, fmt.Sprint(h.now.Unix()), "1", 1),
	} {
		if res := request("game-money-v1\n", invalid); res.Code != 400 {
			t.Fatal("invalid accepted", res.Code, res.Body.String())
		}
	}
	altered := strings.Replace(purchase, `"delta":-500`, `"delta":-501`, 1)
	if res := request("game-money-v1\n", altered); res.Code != 409 {
		t.Fatal("altered retry accepted", res.Code)
	}
	broke := strings.Replace(purchase, strings.Repeat("a", 64), strings.Repeat("b", 64), 1)
	broke = strings.Replace(broke, `"revision":0`, `"revision":1`, 1)
	broke = strings.Replace(broke, `"delta":-500`, `"delta":-2000`, 1)
	if res := request("game-money-v1\n", broke); res.Code != 409 {
		t.Fatal("insufficient accepted", res.Code)
	}
	res := request("game-money-v1\n", load)
	if res.Code != 200 || !strings.Contains(res.Body.String(), `"balance":1500`) || !strings.Contains(res.Body.String(), `"harbour":1`) {
		t.Fatal("not atomic", res.Code, res.Body.String())
	}
}
