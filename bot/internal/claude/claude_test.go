package claude

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestReport(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.Method != http.MethodPost || r.Header.Get("Authorization") != "Bearer tok" ||
			r.Header.Get("anthropic-beta") != "oauth-2025-04-20" {
			t.Errorf("request %s %v", r.Method, r.Header)
		}
		body, _ := io.ReadAll(r.Body)
		if !strings.Contains(string(body), `"max_tokens":1`) {
			t.Errorf("body %s", body)
		}
		h := w.Header()
		h.Set("anthropic-ratelimit-unified-status", "allowed_warning")
		h.Set("anthropic-ratelimit-unified-reset", "1800003600")
		h.Set("anthropic-ratelimit-unified-representative-claim", "seven_day")
		h.Set("anthropic-ratelimit-unified-5h-utilization", "0.25")
		h.Set("anthropic-ratelimit-unified-5h-reset", "1800003600")
		h.Set("anthropic-ratelimit-unified-5h-status", "allowed")
		h.Set("anthropic-ratelimit-unified-7d-utilization", "0.91")
		h.Set("anthropic-ratelimit-unified-7d-reset", "1800300000")
		h.Set("anthropic-ratelimit-unified-7d-status", "allowed_warning")
		w.Write([]byte(`{}`))
	}))
	defer srv.Close()
	now := time.Unix(1_800_000_000, 0)
	c := &Client{Token: "tok", URL: srv.URL, Now: func() time.Time { return now }}

	got, err := c.Report(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"🟢 5-hour: `███░░░░░░░` 25% used · resets <t:1800003600:F> (<t:1800003600:R>)",
		"🟡 Weekly: `█████████░` 91% used · resets <t:1800300000:F> (<t:1800300000:R>)",
		"⚠️ Close to the limit (the weekly limit).",
		"-# As of <t:1800000000:T>",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("report missing %q:\n%s", want, got)
		}
	}

	// Cached for a minute.
	now = now.Add(30 * time.Second)
	c.Report(context.Background())
	if calls.Load() != 1 {
		t.Errorf("calls = %d, want 1 (cached)", calls.Load())
	}
	now = now.Add(time.Minute)
	c.Report(context.Background())
	if calls.Load() != 2 {
		t.Errorf("calls = %d, want 2", calls.Load())
	}
}

func TestReportRejected(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("anthropic-ratelimit-unified-status", "rejected")
		h.Set("anthropic-ratelimit-unified-reset", "1800003600")
		h.Set("anthropic-ratelimit-unified-representative-claim", "five_hour")
		h.Set("anthropic-ratelimit-unified-5h-utilization", "1.02")
		h.Set("anthropic-ratelimit-unified-5h-status", "rejected")
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()
	got, err := (&Client{Token: "tok", URL: srv.URL}).Report(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"🔴 5-hour: `██████████` 102% used\n", "⛔ Limit reached (the 5-hour limit): agent runs will fail until <t:1800003600:F> (<t:1800003600:R>)."} {
		if !strings.Contains(got, want) {
			t.Errorf("report missing %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "Weekly") {
		t.Errorf("unknown window shown:\n%s", got)
	}
}

func TestReportErrors(t *testing.T) {
	if _, err := (*Client)(nil).Report(context.Background()); !errors.Is(err, ErrNoToken) {
		t.Errorf("nil client: %v", err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"error":"invalid token"}`, http.StatusUnauthorized)
	}))
	defer srv.Close()
	_, err := (&Client{Token: "bad", URL: srv.URL}).Report(context.Background())
	if err == nil || !strings.Contains(err.Error(), "401") {
		t.Errorf("err = %v", err)
	}
}
