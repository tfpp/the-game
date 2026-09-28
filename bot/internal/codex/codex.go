// Package codex reads ChatGPT subscription quotas without invoking a model.
// This is the source-derived endpoint used by the Codex CLI, not a stable public API:
// https://github.com/openai/codex/blob/6288753b469615a0b62e8cf0dd65c6e893eb4849/codex-rs/backend-client/src/client/rate_limit_resets.rs
package codex

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	DefaultURL = "https://chatgpt.com/backend-api/wham/usage"
	cacheFor   = time.Minute
	maxBody    = 1 << 20

	weekSeconds = 604800
)

var (
	ErrNoAuth      = errors.New("codex: no ChatGPT login configured")
	ErrAuthExpired = errors.New("codex: ChatGPT login expired or rejected")
)

// Client reads a file-backed Codex login on cache misses. It never refreshes or
// writes credentials: the CLI/operator owns refresh rotation and the file may be
// a read-only secret mount. Replacing it takes effect without a bot restart.
type Client struct {
	AuthFile string
	URL      string // default DefaultURL; overridden by offline tests
	HTTP     *http.Client
	Now      func() time.Time

	mu     sync.Mutex
	cached string
	at     time.Time
}

type auth struct {
	Mode   string `json:"auth_mode"`
	Tokens struct {
		AccessToken string `json:"access_token"`
		AccountID   string `json:"account_id"`
	} `json:"tokens"`
}

type window struct {
	UsedPercent *float64 `json:"used_percent"`
	Seconds     int64    `json:"limit_window_seconds"`
	ResetAt     int64    `json:"reset_at"`
}

type limits struct {
	Allowed      *bool   `json:"allowed"`
	LimitReached bool    `json:"limit_reached"`
	Primary      *window `json:"primary_window"`
	Secondary    *window `json:"secondary_window"`
}

type payload struct {
	Limits *limits `json:"rate_limit"`
}

func (c *Client) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

// Report returns Discord Markdown, caching successful responses for one minute.
// Credentials, response bodies and account IDs never appear in reports or errors.
func (c *Client) Report(ctx context.Context) (string, error) {
	if c == nil || c.AuthFile == "" {
		return "", ErrNoAuth
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.now()
	if c.cached != "" && now.Sub(c.at) >= 0 && now.Sub(c.at) < cacheFor {
		return c.cached, nil
	}
	a, err := readAuth(c.AuthFile)
	if err != nil {
		return "", err
	}
	url := c.URL
	if url == "" {
		url = DefaultURL
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", errors.New("codex: invalid usage endpoint")
	}
	req.Header.Set("Authorization", "Bearer "+a.Tokens.AccessToken)
	if a.Tokens.AccountID != "" {
		req.Header.Set("ChatGPT-Account-Id", a.Tokens.AccountID)
	}
	req.Header.Set("User-Agent", "the-game-bot/usage")
	req.Header.Set("Accept", "application/json")
	// Never forward the account header or bearer token through redirects.
	hc := http.Client{Timeout: 30 * time.Second}
	if c.HTTP != nil {
		hc = *c.HTTP
	}
	hc.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	resp, err := hc.Do(req)
	if err != nil {
		return "", errors.New("codex: usage request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return "", ErrAuthExpired
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("codex: usage endpoint returned HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBody+1))
	if err != nil || len(body) > maxBody {
		return "", errors.New("codex: cannot read usage response")
	}
	var p payload
	if json.Unmarshal(body, &p) != nil {
		return "", errors.New("codex: invalid usage response")
	}
	text, err := format(p, now)
	if err != nil {
		return "", err
	}
	c.cached, c.at = text, now
	return text, nil
}

func readAuth(path string) (auth, error) {
	var a auth
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return a, ErrNoAuth
	}
	if err != nil {
		return a, errors.New("codex: cannot read auth file")
	}
	defer f.Close()
	body, err := io.ReadAll(io.LimitReader(f, maxBody+1))
	if err != nil || len(body) > maxBody || json.Unmarshal(body, &a) != nil {
		return auth{}, errors.New("codex: invalid auth file")
	}
	if (a.Mode != "" && a.Mode != "chatgpt") || a.Tokens.AccessToken == "" {
		return auth{}, ErrNoAuth
	}
	return a, nil
}

// format reports only the main weekly window; short windows and additional
// per-model limits (e.g. gpt-reserve) are deliberately omitted.
func format(p payload, now time.Time) (string, error) {
	l := p.Limits
	if l == nil {
		return "", errors.New("codex: usage response has no recognized limits")
	}
	var line string
	for _, w := range []*window{l.Primary, l.Secondary} {
		if w == nil || w.Seconds != weekSeconds || w.UsedPercent == nil || *w.UsedPercent < 0 || *w.UsedPercent > 10000 {
			continue // absent/invalid telemetry is not zero usage
		}
		used := *w.UsedPercent
		icon := "🟢"
		if used >= 100 {
			icon = "🔴"
		} else if used >= 80 {
			icon = "🟡"
		}
		line = fmt.Sprintf("%s Weekly: %.0f%% used", icon, used)
		if w.ResetAt > 0 && w.ResetAt <= 253402300799 {
			line += fmt.Sprintf(" · resets <t:%d:F> (<t:%d:R>)", w.ResetAt, w.ResetAt)
		}
		break
	}
	lines := []string{}
	if line != "" {
		lines = append(lines, line)
	} else if l.Allowed != nil || l.LimitReached {
		lines = append(lines, "Weekly usage unavailable.")
	}
	if l.LimitReached {
		lines = append(lines, "⛔ Limit reached.")
	} else if l.Allowed != nil && !*l.Allowed {
		lines = append(lines, "⚠️ Requests currently unavailable.")
	}
	if len(lines) == 0 {
		return "", errors.New("codex: usage response has no weekly limit")
	}
	return "**Codex usage limits**\n" + strings.Join(lines, "\n") + fmt.Sprintf("\n-# As of <t:%d:T>", now.Unix()), nil
}
