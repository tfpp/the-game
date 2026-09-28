package codex

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

const testToken = "secret-access-token"
const testAccount = "secret-account-id"
const zeroUsage = `{"rate_limit":{"secondary_window":{"used_percent":0,"limit_window_seconds":604800}}}`

var testNow = time.Unix(1700000000, 0)

func authFile(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "auth.json")
	if err := os.WriteFile(path, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	return path
}
func login(token, account string) string {
	body, _ := json.Marshal(map[string]any{"auth_mode": "chatgpt", "tokens": map[string]string{"access_token": token, "account_id": account}})
	return string(body)
}
func testClient(t *testing.T, handler http.HandlerFunc) *Client {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return &Client{AuthFile: authFile(t, login(testToken, testAccount)), URL: server.URL, HTTP: server.Client(), Now: func() time.Time { return testNow }}
}
func noLeaks(t *testing.T, text string) {
	t.Helper()
	for _, secret := range []string{testToken, testAccount, "private-response-body"} {
		if strings.Contains(text, secret) {
			t.Errorf("output leaked %q", secret)
		}
	}
}

func TestRequestAndFormatting(t *testing.T) {
	for _, account := range []string{"", testAccount} {
		t.Run("account="+account, func(t *testing.T) {
			c := testClient(t, func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodGet || r.URL.Path != "/usage" {
					t.Errorf("request = %s %s", r.Method, r.URL.Path)
				}
				for key, want := range map[string]string{"Authorization": "Bearer " + testToken, "ChatGPT-Account-Id": account, "Accept": "application/json", "User-Agent": "the-game-bot/usage"} {
					if got := r.Header.Get(key); got != want {
						t.Errorf("%s = %q, want %q", key, got, want)
					}
				}
				if _, ok := r.Header[http.CanonicalHeaderKey("x-openai-codex-luna-reserve")]; ok {
					t.Error("reserve header must never be sent")
				}
				fmt.Fprint(w, `{"rate_limit":{"primary_window":{"used_percent":12.6,"limit_window_seconds":18000,"reset_at":1700000300},"secondary_window":{"used_percent":80,"limit_window_seconds":604800,"reset_at":1700600000}},"additional_rate_limits":[{"limit_name":"gpt-reserve","rate_limit":{"secondary_window":{"used_percent":0,"limit_window_seconds":604800},"limit_reached":true}}]}`)
			})
			c.AuthFile = authFile(t, login(testToken, account))
			c.URL += "/usage"
			got, err := c.Report(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			want := "**Codex usage limits**\n🟡 Weekly: 80% used · resets <t:1700600000:F> (<t:1700600000:R>)\n-# As of <t:1700000000:T>"
			if got != want {
				t.Errorf("report:\n%s\nwant:\n%s", got, want)
			}
			noLeaks(t, got)
		})
	}
}

func TestCacheExpiryReloadsReplacedAuth(t *testing.T) {
	var calls atomic.Int32
	c := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		n := calls.Add(1)
		want := "Bearer " + testToken
		if n > 1 {
			want = "Bearer rotated-token"
		}
		if r.Header.Get("Authorization") != want {
			t.Errorf("authorization not reloaded on request %d", n)
		}
		fmt.Fprint(w, zeroUsage)
	})
	now := testNow
	c.Now = func() time.Time { return now }
	first, err := c.Report(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	replacement := filepath.Join(filepath.Dir(c.AuthFile), "replacement.json")
	if err := os.WriteFile(replacement, []byte(login("rotated-token", "")), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(replacement, c.AuthFile); err != nil {
		t.Fatal(err)
	}
	now = now.Add(time.Minute - time.Nanosecond)
	cached, err := c.Report(context.Background())
	if err != nil || cached != first || calls.Load() != 1 {
		t.Fatalf("cache miss: calls=%d err=%v", calls.Load(), err)
	}
	now = now.Add(time.Nanosecond)
	fresh, err := c.Report(context.Background())
	if err != nil || fresh == first || calls.Load() != 2 {
		t.Fatalf("expiry: calls=%d err=%v", calls.Load(), err)
	}
}

func TestAuthFailures(t *testing.T) {
	var calls atomic.Int32
	c := testClient(t, func(w http.ResponseWriter, r *http.Request) { calls.Add(1); fmt.Fprint(w, zeroUsage) })
	cases := []struct {
		name, body string
		missing    bool
		want       error
	}{
		{name: "missing", missing: true, want: ErrNoAuth},
		{name: "empty object", body: `{}`, want: ErrNoAuth},
		{name: "null", body: `null`, want: ErrNoAuth},
		{name: "API key", body: `{"OPENAI_API_KEY":"secret-access-token","auth_mode":"apikey"}`, want: ErrNoAuth},
		{name: "API mode with token", body: `{"auth_mode":"apikey","tokens":{"access_token":"secret-access-token"}}`, want: ErrNoAuth},
		{name: "malformed", body: `{"tokens":"secret-access-token"}`},
		{name: "trailing data", body: login(testToken, "") + ` secret-access-token`},
		{name: "oversized", body: login(testToken, "") + strings.Repeat(" ", maxBody)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c.AuthFile = authFile(t, tc.body)
			if tc.missing {
				if err := os.Remove(c.AuthFile); err != nil {
					t.Fatal(err)
				}
			}
			got, err := c.Report(context.Background())
			if err == nil || got != "" {
				t.Fatalf("got %q, %v", got, err)
			}
			if tc.want != nil && !errors.Is(err, tc.want) {
				t.Errorf("got %v, want %v", err, tc.want)
			}
			noLeaks(t, err.Error())
		})
	}
	for _, client := range []*Client{nil, {}} {
		if _, err := client.Report(context.Background()); !errors.Is(err, ErrNoAuth) {
			t.Errorf("empty client: %v", err)
		}
	}
	if calls.Load() != 0 {
		t.Errorf("auth failures made %d HTTP requests", calls.Load())
	}
}

func TestResponseFailuresAreNotCached(t *testing.T) {
	cases := []struct {
		name   string
		status int
		body   string
		want   error
	}{
		{"unauthorized", 401, "private-response-body", ErrAuthExpired},
		{"forbidden", 403, "private-response-body", ErrAuthExpired},
		{"rate limited", 429, "private-response-body", nil},
		{"server error", 500, "private-response-body", nil},
		{"unavailable", 503, "private-response-body", nil},
		{"malformed", 200, `{"secret-access-token":`, nil},
		{"oversized", 200, zeroUsage + strings.Repeat(" ", maxBody), nil},
		{"unknown", 200, `{"future_schema":0}`, nil},
		{"empty", 200, `{}`, nil},
		{"null", 200, `null`, nil},
		{"empty limits", 200, `{"rate_limit":{}}`, nil},
		{"no weekly window", 200, `{"rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000}}}`, nil},
		{"additional only", 200, `{"additional_rate_limits":[{"limit_name":"gpt-reserve","rate_limit":{"secondary_window":{"used_percent":0,"limit_window_seconds":604800}}}]}`, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var calls atomic.Int32
			c := testClient(t, func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				w.WriteHeader(tc.status)
				fmt.Fprint(w, tc.body)
			})
			for i := 0; i < 2; i++ {
				got, err := c.Report(context.Background())
				if err == nil || got != "" {
					t.Fatalf("got %q, %v", got, err)
				}
				if tc.want != nil && !errors.Is(err, tc.want) {
					t.Errorf("got %v, want %v", err, tc.want)
				}
				if tc.status >= 400 && tc.want == nil && !strings.Contains(err.Error(), fmt.Sprint(tc.status)) {
					t.Errorf("status missing: %v", err)
				}
				noLeaks(t, err.Error())
			}
			if calls.Load() != 2 {
				t.Errorf("failure cached: %d calls", calls.Load())
			}
		})
	}
}

func TestRedirectsRefused(t *testing.T) {
	for _, status := range []int{301, 302, 303, 307, 308} {
		t.Run(fmt.Sprint(status), func(t *testing.T) {
			var reached atomic.Int32
			target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				reached.Add(1)
				if r.Header.Get("Authorization") != "" || r.Header.Get("ChatGPT-Account-Id") != "" {
					t.Error("credentials leaked to redirect target")
				}
				fmt.Fprint(w, zeroUsage)
			}))
			defer target.Close()
			c := testClient(t, func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, status) })
			var policyCalls atomic.Int32
			c.HTTP.CheckRedirect = func(*http.Request, []*http.Request) error { policyCalls.Add(1); return nil }
			got, err := c.Report(context.Background())
			if err == nil || got != "" || !strings.Contains(err.Error(), fmt.Sprint(status)) {
				t.Fatalf("redirect: %q, %v", got, err)
			}
			noLeaks(t, err.Error())
			if reached.Load() != 0 || policyCalls.Load() != 0 {
				t.Error("redirect was followed or caller policy used")
			}
			// The client's supplied HTTP configuration must not be mutated.
			_ = c.HTTP.CheckRedirect(nil, nil)
			if policyCalls.Load() != 1 {
				t.Error("caller redirect policy was overwritten")
			}
		})
	}
}

func TestMissingWindowsAndZeroUsage(t *testing.T) {
	cases := []struct {
		name, body, want string
		reject           string
	}{
		{"zero", zeroUsage, "🟢 Weekly: 0% used", "unavailable"},
		{"five-hour hidden", `{"rate_limit":{"primary_window":{"used_percent":40,"limit_window_seconds":18000},"secondary_window":{"used_percent":1,"limit_window_seconds":604800}}}`, "Weekly: 1% used", "hour"},
		{"missing windows", `{"rate_limit":{"allowed":true}}`, "Weekly usage unavailable.", "0%"},
		{"missing percent", `{"rate_limit":{"allowed":false,"secondary_window":{"limit_window_seconds":604800,"reset_at":1700000300}}}`, "Requests currently unavailable.", "0%"},
		{"limit reached", `{"rate_limit":{"limit_reached":true}}`, "Limit reached.", "0%"},
		{"invalid percent", `{"rate_limit":{"allowed":true,"primary_window":{"used_percent":-1,"limit_window_seconds":604800},"secondary_window":{"used_percent":10001,"limit_window_seconds":604800}}}`, "Weekly usage unavailable.", "% used"},
		{"invalid reset", `{"rate_limit":{"secondary_window":{"used_percent":0,"limit_window_seconds":604800,"reset_at":253402300800}}}`, "Weekly: 0% used", "resets"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := testClient(t, func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, tc.body) })
			got, err := c.Report(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(got, tc.want) || strings.Contains(got, tc.reject) {
				t.Errorf("unexpected report: %s", got)
			}
		})
	}
}

func TestConcurrentCache(t *testing.T) {
	var calls atomic.Int32
	var clock atomic.Int64
	clock.Store(testNow.Unix())
	c := testClient(t, func(w http.ResponseWriter, r *http.Request) { calls.Add(1); fmt.Fprint(w, zeroUsage) })
	c.Now = func() time.Time { return time.Unix(clock.Load(), 0) }
	for round := 1; round <= 2; round++ {
		start := make(chan struct{})
		var wg sync.WaitGroup
		results := make(chan string, 32)
		for i := 0; i < 32; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-start
				got, err := c.Report(context.Background())
				if err != nil {
					t.Errorf("Report: %v", err)
				}
				results <- got
			}()
		}
		close(start)
		wg.Wait()
		close(results)
		var first string
		for got := range results {
			if got == "" {
				t.Error("empty report")
			}
			if first == "" {
				first = got
			}
			if got != first {
				t.Error("concurrent reports differ")
			}
		}
		if got := calls.Load(); got != int32(round) {
			t.Errorf("round %d: %d requests", round, got)
		}
		clock.Add(60)
	}
}
