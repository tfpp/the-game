package webhook

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"
)

// GameChatPoster is the existing Discord Post interface. No mention allowlist is supplied.
type GameChatPoster interface {
	Post(context.Context, string, string, ...string) error
}

// GameChatHandler accepts only signed public messages from the dedicated game server.
// The channel is configured by the operator, never selected by the request.
// Replay tracking is bounded and in memory; restarting the bot clears it.
type GameChatHandler struct {
	Key       []byte
	ChannelID string
	Poster    GameChatPoster
	mu        sync.Mutex
	seen      map[string]time.Time
}

var chatEventID = regexp.MustCompile(`^[a-f0-9]{32}:[0-9]{1,12}$`)

type gameChatMessage struct {
	ID        string `json:"id"`
	Timestamp int64  `json:"timestamp"`
	Sender    string `json:"sender"`
	Text      string `json:"text"`
}

func (h *GameChatHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if len(h.Key) < 32 || h.ChannelID == "" || h.Poster == nil {
		http.Error(w, "relay disabled", http.StatusServiceUnavailable)
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 4096))
	if err != nil {
		http.Error(w, "body too large", http.StatusRequestEntityTooLarge)
		return
	}
	mac := hmac.New(sha256.New, h.Key)
	mac.Write([]byte("game-chat-v1\n"))
	mac.Write(body)
	signature, err := hex.DecodeString(r.Header.Get("X-Game-Chat-Signature"))
	if err != nil || !hmac.Equal(signature, mac.Sum(nil)) {
		http.Error(w, "invalid signature", http.StatusUnauthorized)
		return
	}
	var msg gameChatMessage
	now := time.Now()
	if json.Unmarshal(body, &msg) != nil || !utf8.Valid(body) || !chatEventID.MatchString(msg.ID) ||
		strings.TrimSpace(msg.Sender) == "" || utf8.RuneCountInString(msg.Sender) > 64 ||
		strings.TrimSpace(msg.Text) == "" || utf8.RuneCountInString(msg.Text) > 120 ||
		strings.HasPrefix(strings.TrimSpace(msg.Text), "/") ||
		msg.Timestamp < now.Unix()-300 || msg.Timestamp > now.Unix()+300 {
		http.Error(w, "invalid message", http.StatusBadRequest)
		return
	}
	// Serialize posting as well as deduplication: simultaneous retries cannot double-post.
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.seen == nil {
		h.seen = make(map[string]time.Time)
	}
	for id, expiry := range h.seen {
		if !expiry.After(now) {
			delete(h.seen, id)
		}
	}
	if _, ok := h.seen[msg.ID]; ok {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if len(h.seen) >= 4096 {
		http.Error(w, "relay busy", http.StatusServiceUnavailable)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	if h.Poster.Post(ctx, h.ChannelID, gameChatLine(msg.Sender, msg.Text)) != nil {
		// Do not log message content or upstream errors that could include it.
		http.Error(w, "Discord unavailable", http.StatusBadGateway)
		return
	}
	h.seen[msg.ID] = now.Add(10 * time.Minute)
	w.WriteHeader(http.StatusNoContent)
}

// A literal code block prevents links/markdown from impersonating bot notifications.
// Replace backticks so a player's text cannot close the block; flatten control characters.
func gameChatLine(sender, text string) string {
	clean := func(s string) string {
		return strings.Map(func(r rune) rune {
			if r == '`' {
				return 'ˋ'
			}
			if unicode.IsControl(r) || r == '\u2028' || r == '\u2029' {
				return ' '
			}
			return r
		}, s)
	}
	return "```text\n" + clean(sender) + ": " + clean(text) + "\n```"
}
