package webhook

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type chatPost struct {
	channel, content string
	pings            []string
}
type chatRecorder struct {
	posts []chatPost
	fail  bool
}

func (p *chatRecorder) Post(_ context.Context, channel, content string, ping ...string) error {
	if p.fail {
		return errors.New("unavailable")
	}
	p.posts = append(p.posts, chatPost{channel, content, ping})
	return nil
}

func chatFixture() (*GameChatHandler, *chatRecorder, gameChatMessage) {
	p := &chatRecorder{}
	h := &GameChatHandler{Key: []byte(strings.Repeat("k", 32)), ChannelID: "123", Poster: p}
	m := gameChatMessage{ID: strings.Repeat("a", 32) + ":1", Timestamp: time.Now().Unix(), Sender: "Alice", Text: "hello"}
	return h, p, m
}
func chatRequest(h *GameChatHandler, body string, signed bool) int {
	r := httptest.NewRequest(http.MethodPost, "/bot/game-chat", strings.NewReader(body))
	if signed {
		mac := hmac.New(sha256.New, h.Key)
		mac.Write([]byte("game-chat-v1\n" + body))
		r.Header.Set("X-Game-Chat-Signature", hex.EncodeToString(mac.Sum(nil)))
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w.Code
}
func chatJSON(m gameChatMessage) string { b, _ := json.Marshal(m); return string(b) }

func TestGameChatAcceptedAndConcurrentRetriesDeduplicated(t *testing.T) {
	h, p, m := chatFixture()
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if code := chatRequest(h, chatJSON(m), true); code != 204 {
				t.Errorf("status %d", code)
			}
		}()
	}
	wg.Wait()
	if len(p.posts) != 1 || p.posts[0].channel != "123" || len(p.posts[0].pings) != 0 || p.posts[0].content != "```text\nAlice: hello\n```" {
		t.Fatalf("posts: %+v", p.posts)
	}
	m.ID = strings.Repeat("a", 32) + ":2"
	if chatRequest(h, chatJSON(m), true) != 204 || len(p.posts) != 2 {
		t.Fatal("new event not posted")
	}
}

func TestGameChatRejectsUnsignedTamperedAndWrongDomain(t *testing.T) {
	h, p, m := chatFixture()
	if chatRequest(h, chatJSON(m), false) != 401 {
		t.Fatal("unsigned accepted")
	}
	for _, prefix := range []string{"game-money-v1\n", "game-chat-v1\n"} {
		r := httptest.NewRequest("POST", "/bot/game-chat", strings.NewReader(chatJSON(m)+" "))
		mac := hmac.New(sha256.New, h.Key)
		mac.Write([]byte(prefix + chatJSON(m)))
		r.Header.Set("X-Game-Chat-Signature", hex.EncodeToString(mac.Sum(nil)))
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != 401 {
			t.Fatalf("wrong domain/tampering accepted: %d", w.Code)
		}
	}
	if len(p.posts) != 0 {
		t.Fatal("posted unauthenticated input")
	}
}

func TestGameChatValidation(t *testing.T) {
	for name, mutate := range map[string]func(*gameChatMessage){
		"blank sender": func(m *gameChatMessage) { m.Sender = " " },
		"long sender":  func(m *gameChatMessage) { m.Sender = strings.Repeat("a", 65) },
		"empty":        func(m *gameChatMessage) { m.Text = " " },
		"long unicode": func(m *gameChatMessage) { m.Text = strings.Repeat("😃", 121) },
		"command":      func(m *gameChatMessage) { m.Text = " /suicide" },
		"expired":      func(m *gameChatMessage) { m.Timestamp -= 301 },
		"future":       func(m *gameChatMessage) { m.Timestamp += 301 },
		"invalid id":   func(m *gameChatMessage) { m.ID = "account123" },
	} {
		t.Run(name, func(t *testing.T) {
			h, p, m := chatFixture()
			mutate(&m)
			if code := chatRequest(h, chatJSON(m), true); code != 400 || len(p.posts) != 0 {
				t.Fatalf("status %d posts %+v", code, p.posts)
			}
		})
	}
	h, _, _ := chatFixture()
	if chatRequest(h, "{", true) != 400 || chatRequest(h, strings.Repeat("x", 4097), true) != 413 {
		t.Fatal("invalid body accepted")
	}
	r := httptest.NewRequest("GET", "/bot/game-chat", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != 405 {
		t.Fatal("GET accepted")
	}
	h.Key = nil
	if chatRequest(h, "{}", false) != 503 {
		t.Fatal("disabled handler accepted")
	}
}

func TestGameChatFailureCanRetryAndCacheIsBounded(t *testing.T) {
	h, p, m := chatFixture()
	p.fail = true
	if chatRequest(h, chatJSON(m), true) != 502 || len(h.seen) != 0 {
		t.Fatal("failure marked delivered")
	}
	p.fail = false
	if chatRequest(h, chatJSON(m), true) != 204 || len(p.posts) != 1 {
		t.Fatal("retry failed")
	}
	h.seen["expired"] = time.Now().Add(-time.Second)
	m.ID = strings.Repeat("b", 32) + ":1"
	if chatRequest(h, chatJSON(m), true) != 204 {
		t.Fatal("next failed")
	}
	if _, ok := h.seen["expired"]; ok {
		t.Fatal("expired cache not purged")
	}
	for len(h.seen) < 4096 {
		h.seen[strings.Repeat("x", len(h.seen)+1)] = time.Now().Add(time.Minute)
	}
	m.ID = strings.Repeat("c", 32) + ":1"
	if chatRequest(h, chatJSON(m), true) != 503 {
		t.Fatal("cache unbounded")
	}
}

func TestGameChatSignatureMatchesGodotVector(t *testing.T) {
	mac := hmac.New(sha256.New, []byte("fixture-key-not-a-secret-1234567890"))
	mac.Write([]byte("game-chat-v1\n" + `{"sender":"Alice","text":"hello"}`))
	if got := hex.EncodeToString(mac.Sum(nil)); got != "e6f01791e8ef0b7e291f760faceedd89e6464c7d61f581a7cff65c5905e3d05c" {
		t.Fatalf("signature %s", got)
	}
}

func TestGameChatRendersPlayerTextLiterally(t *testing.T) {
	h, p, m := chatFixture()
	m.Sender = "Alice\n```"
	m.Text = "```\n@everyone <@123> **fake** [link](https://example.invalid)"
	if chatRequest(h, chatJSON(m), true) != 204 {
		t.Fatal("not posted")
	}
	line := p.posts[0].content
	if strings.Count(line, "```") != 2 || strings.Count(line, "\n") != 2 || len(p.posts[0].pings) != 0 {
		t.Fatalf("unsafe formatting %q", line)
	}
}
