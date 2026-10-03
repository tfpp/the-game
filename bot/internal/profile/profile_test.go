package profile

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestLookup(t *testing.T) {
	const key = "dedicated-profile-test-key-32-bytes"
	for _, tc := range []struct {
		name      string
		code      int
		body      string
		wantError bool
		notFound  bool
	}{
		{"found", 200, `{"display_name":"Gamer","playtime_seconds":3605}`, false, false},
		{"unlinked", 404, "{}", true, true},
		{"unauthorized", 401, "{}", true, false},
		{"offline", 503, "{}", true, false},
		{"invalid json", 200, "{", true, false},
		{"negative time", 200, `{"playtime_seconds":-1}`, true, false},
		{"oversized", 200, strings.Repeat(" ", 4097), true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/api/bot/profile/123" || r.Header.Get("Authorization") != "Bearer "+key {
					t.Error("incorrect request")
				}
				w.WriteHeader(tc.code)
				w.Write([]byte(tc.body))
			}))
			defer srv.Close()
			c, err := New(srv.URL+"/api", key)
			if err != nil {
				t.Fatal(err)
			}
			p, err := c.Lookup(context.Background(), "123")
			if (err != nil) != tc.wantError || errors.Is(err, ErrNotFound) != tc.notFound {
				t.Fatal(p, err)
			}
			if !tc.wantError && (p.DisplayName != "Gamer" || p.PlaytimeSeconds != 3605) {
				t.Fatal(p)
			}
		})
	}
}

func TestConfigurationRedirectAndCancellation(t *testing.T) {
	key := strings.Repeat("k", 32)
	for _, u := range []string{"", "file:///api", "https://user:pass@api.test", "https://api.test?query=1", "https://api.test#fragment"} {
		if _, err := New(u, key); err == nil {
			t.Fatal("accepted", u)
		}
	}
	if _, err := New("https://api.test/api", "short"); err == nil {
		t.Fatal("accepted short key")
	}
	called := false
	target := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true }))
	defer target.Close()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, 302) }))
	defer srv.Close()
	c, _ := New(srv.URL+"/api", key)
	if _, err := c.Lookup(context.Background(), "123"); err == nil || called {
		t.Fatal("followed redirect")
	}
	if _, err := c.Lookup(context.Background(), "../123"); err == nil {
		t.Fatal("accepted path")
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Nanosecond)
	defer cancel()
	if _, err := c.Lookup(ctx, "123"); err == nil {
		t.Fatal("ignored cancellation")
	}
}
