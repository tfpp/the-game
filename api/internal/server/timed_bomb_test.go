package server

import (
	"bytes"
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

func TestTimedBombEndpointAuthenticationSchemaAndPrivacy(t *testing.T) {
	h := newHarness(t)
	request := func(body []byte, domain string, key []byte) *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/api/game/timed-bomb", bytes.NewReader(body))
		mac := hmac.New(sha256.New, key)
		mac.Write([]byte(domain + "\n"))
		mac.Write(body)
		req.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		res := httptest.NewRecorder()
		h.h.ServeHTTP(res, req)
		return res
	}
	body := []byte(fmt.Sprintf(`{"action":"status","timestamp":%d}`, h.now.Unix()))
	for _, auth := range []struct {
		domain string
		key    []byte
	}{
		{"game-timed-bomb-v1", []byte("client-session")},
		{"game-money-v1", testKey},
	} {
		if res := request(body, auth.domain, auth.key); res.Code != 401 {
			t.Fatal(res.Code)
		}
	}
	result := request(body, "game-timed-bomb-v1", testKey)
	if result.Code != 200 {
		t.Fatal(result.Code)
	}
	var snapshot store.BombSnapshot
	if err := json.Unmarshal(result.Body.Bytes(), &snapshot); err != nil {
		t.Fatal(err)
	}
	if snapshot.Deadline != h.now.Unix()+86400 || snapshot.State != "armed" {
		t.Fatal(snapshot)
	}
	var public map[string]any
	json.Unmarshal(result.Body.Bytes(), &public)
	if len(public) != 4 || strings.Contains(result.Body.String(), `"code"`) {
		t.Fatal("unexpected private response field")
	}
	for _, invalid := range []string{
		fmt.Sprintf(`{"action":"reset","timestamp":%d}`, h.now.Unix()),
		fmt.Sprintf(`{"action":"status","timestamp":%d}`, h.now.Unix()-61),
		fmt.Sprintf(`{"action":"defuse","code":"123","timestamp":%d}`, h.now.Unix()),
		fmt.Sprintf(`{"action":"defuse","code":1234,"timestamp":%d}`, h.now.Unix()),
		fmt.Sprintf(`{"action":"status","code":"1234","timestamp":%d}`, h.now.Unix()),
	} {
		if res := request([]byte(invalid), "game-timed-bomb-v1", testKey); res.Code != 400 {
			t.Fatal(res.Code)
		}
	}
}
