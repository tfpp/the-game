// Package claude reports the agent's Claude subscription usage limits for /usage.
//
// The agent authenticates with a `claude setup-token` token, which can't read the
// account's usage endpoint. Every Messages API response carries the subscription's
// rate-limit state in its anthropic-ratelimit-unified-* headers, though, so the client
// sends the smallest possible request and reads those.
package claude

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	DefaultURL = "https://api.anthropic.com/v1/messages"
	// probeModel is the cheapest model; the probe asks for a single output token.
	probeModel = "claude-haiku-4-5"
	// cacheFor bounds how often /usage spends a request on the subscription.
	cacheFor = time.Minute
)

// Window is one rate-limit window of the subscription.
type Window struct {
	Utilization float64   // 0 to 1 (can pass 1 once over the limit)
	Resets      time.Time // zero if unknown
	Status      string    // "allowed", "allowed_warning" or "rejected"; "" if unknown
}

// Usage is the subscription's state as of At.
type Usage struct {
	Status        string // overall: "allowed", "allowed_warning" or "rejected"
	Resets        time.Time
	Claim         string // the window that limits right now, e.g. "five_hour"
	FiveHour      *Window
	SevenDay      *Window
	OverageStatus string
	OverageResets time.Time
	OverageReason string // why overage is disabled, if it is
	At            time.Time
}

// Client probes the usage limits of the subscription Token belongs to.
type Client struct {
	Token string
	URL   string       // default DefaultURL
	HTTP  *http.Client // default http.DefaultClient
	Now   func() time.Time

	mu     sync.Mutex
	cached *Usage
}

func (c *Client) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

// Usage returns the current limits, probing at most once per minute.
func (c *Client) Usage(ctx context.Context) (*Usage, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cached != nil && c.now().Sub(c.cached.At) < cacheFor {
		return c.cached, nil
	}
	u, err := c.probe(ctx)
	if err != nil {
		return nil, err
	}
	c.cached = u
	return u, nil
}

// The system prompt subscription tokens need to be accepted by the Messages API.
const probeBody = `{"model":"` + probeModel + `","max_tokens":1,` +
	`"system":"You are Claude Code, Anthropic's official CLI for Claude.",` +
	`"messages":[{"role":"user","content":"hi"}]}`

func (c *Client) probe(ctx context.Context) (*Usage, error) {
	url := c.URL
	if url == "" {
		url = DefaultURL
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(probeBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.Token)
	req.Header.Set("anthropic-version", "2023-06-01")
	req.Header.Set("anthropic-beta", "oauth-2025-04-20")
	req.Header.Set("Content-Type", "application/json")
	hc := c.HTTP
	if hc == nil {
		hc = http.DefaultClient
	}
	resp, err := hc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	// A request refused for being over the limit (429) still carries the headers.
	u := parse(resp.Header, c.now())
	if u.Status == "" {
		return nil, fmt.Errorf("claude: %s without rate-limit headers: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	return u, nil
}

const prefix = "Anthropic-Ratelimit-Unified-"

func parse(h http.Header, now time.Time) *Usage {
	u := &Usage{
		Status:        h.Get(prefix + "Status"),
		Resets:        unix(h.Get(prefix + "Reset")),
		Claim:         h.Get(prefix + "Representative-Claim"),
		FiveHour:      window(h, "5h"),
		SevenDay:      window(h, "7d"),
		OverageStatus: h.Get(prefix + "Overage-Status"),
		OverageResets: unix(h.Get(prefix + "Overage-Reset")),
		OverageReason: h.Get(prefix + "Overage-Disabled-Reason"),
		At:            now,
	}
	return u
}

func window(h http.Header, name string) *Window {
	p := prefix + name + "-"
	util, err := strconv.ParseFloat(h.Get(p+"Utilization"), 64)
	if err != nil {
		return nil
	}
	return &Window{Utilization: util, Resets: unix(h.Get(p + "Reset")), Status: h.Get(p + "Status")}
}

func unix(s string) time.Time {
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil || n <= 0 {
		return time.Time{}
	}
	return time.Unix(n, 0)
}

// ErrNoToken is returned by Report when no token is configured.
var ErrNoToken = errors.New("claude: no token configured")

// Report is the /usage answer: the limits as Discord markdown.
func (c *Client) Report(ctx context.Context) (string, error) {
	if c == nil || c.Token == "" {
		return "", ErrNoToken
	}
	u, err := c.Usage(ctx)
	if err != nil {
		return "", err
	}
	return Format(u), nil
}

var claimNames = map[string]string{
	"five_hour":      "the 5-hour limit",
	"seven_day":      "the weekly limit",
	"seven_day_opus": "the weekly Opus limit",
}

// Format renders u as Discord markdown.
func Format(u *Usage) string {
	var b strings.Builder
	b.WriteString("**Claude usage limits**\n")
	line := func(label string, w *Window) {
		if w == nil {
			return
		}
		fmt.Fprintf(&b, "%s %s: %s %.0f%% used", icon(w.Status, w.Utilization), label, bar(w.Utilization), w.Utilization*100)
		if !w.Resets.IsZero() {
			fmt.Fprintf(&b, " · resets %s", when(w.Resets))
		}
		b.WriteString("\n")
	}
	line("5-hour", u.FiveHour)
	line("Weekly", u.SevenDay)
	switch u.Status {
	case "rejected":
		b.WriteString("⛔ Limit reached")
		if name := claimNames[u.Claim]; name != "" {
			b.WriteString(" (" + name + ")")
		}
		if !u.Resets.IsZero() {
			fmt.Fprintf(&b, ": agent runs will fail until %s", when(u.Resets))
		}
		b.WriteString(".\n")
	case "allowed_warning":
		b.WriteString("⚠️ Close to the limit")
		if name := claimNames[u.Claim]; name != "" {
			b.WriteString(" (" + name + ")")
		}
		b.WriteString(".\n")
	}
	if u.OverageStatus != "" && u.OverageStatus != "rejected" {
		fmt.Fprintf(&b, "Extra usage: %s\n", strings.ReplaceAll(u.OverageStatus, "_", " "))
	}
	fmt.Fprintf(&b, "-# As of <t:%d:T>", u.At.Unix())
	return b.String()
}

// when is t as a Discord timestamp: the full local date and time, then how long from now.
func when(t time.Time) string {
	return fmt.Sprintf("<t:%d:F> (<t:%d:R>)", t.Unix(), t.Unix())
}

func icon(status string, util float64) string {
	switch {
	case status == "rejected" || util >= 1:
		return "🔴"
	case status == "allowed_warning" || util >= 0.8:
		return "🟡"
	default:
		return "🟢"
	}
}

// bar is a 10-cell progress bar of util.
func bar(util float64) string {
	n := int(util*10 + 0.5)
	n = max(0, min(10, n))
	return "`" + strings.Repeat("█", n) + strings.Repeat("░", 10-n) + "`"
}
