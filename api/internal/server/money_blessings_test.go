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
)

func TestBlessedSlotExactOdds(t *testing.T) {
	for stacks := 0; stacks <= 5; stacks++ {
		wins := 0
		symbols := [5]int{}
		outcomes := map[[3]int]bool{}
		for ticket := 0; ticket < 125; ticket++ {
			reels := slotReels(ticket, stacks)
			outcomes[reels] = true
			for _, symbol := range reels {
				if symbol < 0 || symbol > 4 {
					t.Fatal(reels)
				}
			}
			if reels[0] == reels[1] && reels[1] == reels[2] {
				wins++
				symbols[reels[0]]++
			}
		}
		if wins != 5+10*stacks {
			t.Fatalf("stacks %d: %d wins", stacks, wins)
		}
		for _, count := range symbols {
			if count != 1+2*stacks {
				t.Fatal(symbols)
			}
		}
		if stacks == 0 && len(outcomes) != 125 {
			t.Fatal("changed unblessed distribution")
		}
	}
}

func TestGameMoneyBlessingsValidatedAndReplayStable(t *testing.T) {
	h := newHarness(t)
	account, err := h.srv.store.CreateEmailAccount(context.Background(), "blessed@example.com", "hash", "Alice", h.now)
	if err != nil {
		t.Fatal(err)
	}
	request := func(stacks int, key []byte) *httptest.ResponseRecorder {
		body := []byte(fmt.Sprintf(`{"account_id":%d,"action":"spin","id":"%s","timestamp":%d,"blessings":%d}`, account.ID, strings.Repeat("a", 64), h.now.Unix(), stacks))
		req := httptest.NewRequest("POST", "/api/game/money", bytes.NewReader(body))
		mac := hmac.New(sha256.New, key)
		mac.Write([]byte("game-money-v1\n"))
		mac.Write(body)
		req.Header.Set("X-Game-Signature", hex.EncodeToString(mac.Sum(nil)))
		res := httptest.NewRecorder()
		h.h.ServeHTTP(res, req)
		return res
	}
	if res := request(5, []byte("client-session")); res.Code != 401 {
		t.Fatal(res.Code)
	}
	for _, stacks := range []int{-1, 6} {
		if res := request(stacks, testKey); res.Code != 400 {
			t.Fatal(res.Code, res.Body.String())
		}
	}
	first := request(5, testKey)
	if first.Code != 200 {
		t.Fatal(first.Body.String())
	}
	// A retried settled operation must not reroll, even after blessings are consumed.
	second := request(0, testKey)
	if second.Code != 200 || second.Body.String() != first.Body.String() {
		t.Fatal(second.Body.String())
	}
}
