package server

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestBotProfileAccessAndSignedHeartbeatIntegration(t *testing.T) {
	h := newHarness(t)
	const key = "dedicated-profile-test-key-32-bytes"
	a, err := h.srv.store.CreateEmailAccount(context.Background(), "private@example.com", "private-hash", "Gamer", h.now)
	if err != nil {
		t.Fatal(err)
	}
	if err := h.srv.store.LinkDiscord(context.Background(), a.ID, "123", "private-username", h.now); err != nil {
		t.Fatal(err)
	}
	path := "/api/bot/profile/123"
	h.expect(h.do("GET", path, key, nil), 401, "unauthorized") // disabled
	h.srv.cfg.ProfileKey = []byte(key)
	for _, token := range []string{"", "wrong", string(testKey)} {
		h.expect(h.do("GET", path, token, nil), 401, "unauthorized")
	}
	for i := 0; i < 2; i++ {
		raw := []byte(fmt.Sprintf(`{"account_id":%d,"action":"balance","timestamp":%d}`, a.ID, h.now.Unix()))
		request := httptest.NewRequest("POST", "/api/game/money", bytes.NewReader(raw))
		mac := hmac.New(sha256.New, testKey)
		mac.Write([]byte("game-money-v1\n"))
		mac.Write(raw)
		request.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		rec := httptest.NewRecorder()
		h.h.ServeHTTP(rec, request)
		if rec.Code != 200 {
			t.Fatal(rec.Body.String())
		}
		h.now = h.now.Add(5 * time.Second)
	}
	r := h.do("GET", path, key, nil)
	h.expect(r, 200, "")
	if len(r.body) != 2 || r.str("display_name") != "Gamer" || r.body["playtime_seconds"] != float64(5) || r.header.Get("Cache-Control") != "no-store" {
		t.Fatal(r)
	}
	// Lookup is read-only, never counting time at query time.
	h.now = h.now.Add(time.Hour)
	h.expect(h.do("GET", path, key, nil), 200, "")
	h.expect(h.do("GET", "/api/bot/profile/999", key, nil), 404, "not_found")
	h.expect(h.do("GET", "/api/bot/profile/not-a-user", key, nil), 400, "bad_request")
	h.expect(h.do("GET", "/api/bot/profile/"+strings.Repeat("9", 21), key, nil), 400, "bad_request")
	h.expect(h.do("POST", "/api/game/money", key, map[string]any{"account_id": a.ID}), 401, "unauthorized")
}
