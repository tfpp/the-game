package github

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func testKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func TestParseKey(t *testing.T) {
	k := testKey(t)
	pkcs1 := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(k)})
	der, _ := x509.MarshalPKCS8PrivateKey(k)
	pkcs8 := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	for _, b := range [][]byte{pkcs1, pkcs8} {
		got, err := ParseKey(b)
		if err != nil || !got.Equal(k) {
			t.Errorf("ParseKey: %v", err)
		}
	}
	if _, err := ParseKey([]byte("nope")); err == nil {
		t.Error("garbage parsed")
	}
}

func TestJWT(t *testing.T) {
	k := testKey(t)
	now := time.Unix(1_800_000_000, 0)
	a := &App{ClientID: "Iv1.abc", Key: k, Now: func() time.Time { return now }}
	tok, err := a.JWT()
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		t.Fatalf("jwt %q", tok)
	}
	sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
	sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if err := rsa.VerifyPKCS1v15(&k.PublicKey, crypto.SHA256, sum[:], sig); err != nil {
		t.Fatalf("signature: %v", err)
	}
	payload, _ := base64.RawURLEncoding.DecodeString(parts[1])
	var claims struct {
		Iat, Exp int64
		Iss      string
	}
	json.Unmarshal(payload, &claims)
	if claims.Iss != "Iv1.abc" || claims.Iat != now.Unix()-60 || claims.Exp != now.Unix()+540 {
		t.Errorf("claims %+v", claims)
	}
}

func TestTokenCachingAndCalls(t *testing.T) {
	var tokens atomic.Int32
	now := time.Unix(1_800_000_000, 0)
	var dispatched map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		switch {
		case r.URL.Path == "/repos/o/r/installation":
			if !strings.HasPrefix(auth, "Bearer ") {
				t.Errorf("installation lookup auth %q", auth)
			}
			io.WriteString(w, `{"id": 77}`)
		case r.URL.Path == "/app/installations/77/access_tokens" && r.Method == http.MethodPost:
			tokens.Add(1)
			io.WriteString(w, `{"token":"ghs_1","expires_at":"`+now.Add(time.Hour).UTC().Format(time.RFC3339)+`"}`)
		case r.URL.Path == "/repos/o/r/actions/workflows/agent.yml/dispatches":
			if auth != "token ghs_1" {
				t.Errorf("dispatch auth %q", auth)
			}
			json.NewDecoder(r.Body).Decode(&dispatched)
			w.WriteHeader(http.StatusNoContent)
		case r.URL.Path == "/repos/o/r/issues" && r.Method == http.MethodPost:
			w.WriteHeader(http.StatusCreated)
			io.WriteString(w, `{"number": 5, "title": "t", "html_url": "u"}`)
		case r.URL.Path == "/repos/o/r/issues/5/comments":
			if r.URL.Query().Get("since") == "" {
				t.Error("comments without since")
			}
			io.WriteString(w, `[{"id":1,"body":"hi","user":{"login":"a[bot]","type":"Bot"}}]`)
		default:
			w.WriteHeader(http.StatusNotFound)
			io.WriteString(w, `{"message":"Not Found"}`)
		}
	}))
	defer srv.Close()
	a := &App{ClientID: "c", Key: testKey(t), Repo: "o/r", BaseURL: srv.URL, Now: func() time.Time { return now }}
	ctx := context.Background()

	if err := a.Dispatch(ctx, "agent.yml", "main", map[string]string{"number": "5"}); err != nil {
		t.Fatal(err)
	}
	if dispatched["ref"] != "main" || dispatched["inputs"].(map[string]any)["number"] != "5" {
		t.Errorf("dispatch body %v", dispatched)
	}
	is, err := a.CreateIssue(ctx, "t", "b")
	if err != nil || is.Number != 5 {
		t.Fatalf("issue %+v %v", is, err)
	}
	cs, err := a.Comments(ctx, 5, now)
	if err != nil || len(cs) != 1 || cs[0].User.Type != "Bot" {
		t.Fatalf("comments %+v %v", cs, err)
	}
	if tokens.Load() != 1 {
		t.Errorf("token fetched %d times, want 1 (cached)", tokens.Load())
	}
	now = now.Add(56 * time.Minute) // within five minutes of expiry
	a.Dispatch(ctx, "agent.yml", "main", nil)
	if tokens.Load() != 2 {
		t.Errorf("token not refreshed: %d", tokens.Load())
	}
	_, err = a.WorkflowRuns(ctx, "missing.yml", now)
	var apiErr *APIError
	if !errors.As(err, &apiErr) || apiErr.Status != 404 || apiErr.Message != "Not Found" {
		t.Errorf("want APIError 404, got %v", err)
	}
}

func TestValidSignature(t *testing.T) {
	secret := []byte("It's a Secret to Everybody")
	body := []byte("Hello, World!")
	// The example from GitHub's webhook documentation.
	good := "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"
	if !ValidSignature(secret, body, good) {
		t.Error("documented signature rejected")
	}
	for _, bad := range []string{"", "sha256=00", "sha1=757107ea", good[:len(good)-1] + "0"} {
		if ValidSignature(secret, body, bad) {
			t.Errorf("accepted %q", bad)
		}
	}
	if ValidSignature(nil, body, good) {
		t.Error("accepted with an empty secret")
	}
}

func TestMergeCalls(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	var merged, updated map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch p := r.URL.Path; {
		case p == "/repos/o/r/installation":
			io.WriteString(w, `{"id": 77}`)
		case p == "/app/installations/77/access_tokens":
			io.WriteString(w, `{"token":"ghs_1","expires_at":"`+now.Add(time.Hour).UTC().Format(time.RFC3339)+`"}`)
		case p == "/repos/o/r/contents/.github/CODEOWNERS" && r.URL.Query().Get("ref") == "main":
			io.WriteString(w, `{"encoding":"base64","content":"L2JvdC8g\nQHg=\n"}`)
		case p == "/repos/o/r/pulls/4/files":
			if r.URL.Query().Get("page") == "1" {
				io.WriteString(w, `[{"filename":"a"},{"filename":"b","previous_filename":"c"}]`)
			} else {
				io.WriteString(w, `[]`)
			}
		case p == "/repos/o/r/pulls/4/update-branch" && r.Method == http.MethodPut:
			json.NewDecoder(r.Body).Decode(&updated)
			w.WriteHeader(http.StatusAccepted)
			io.WriteString(w, `{"message":"Updating pull request branch."}`)
		case p == "/repos/o/r/pulls/4/merge" && r.Method == http.MethodPut:
			json.NewDecoder(r.Body).Decode(&merged)
			io.WriteString(w, `{"sha":"m1","merged":true}`)
		case p == "/repos/o/r/pulls/5/merge":
			w.WriteHeader(http.StatusConflict)
			io.WriteString(w, `{"message":"Head branch was modified. Review and try the merge again."}`)
		case p == "/repos/o/r/compare/main...agent/4-x":
			io.WriteString(w, `{"status":"diverged","ahead_by":1,"behind_by":2}`)
		default:
			w.WriteHeader(http.StatusNotFound)
			io.WriteString(w, `{"message":"Not Found"}`)
		}
	}))
	defer srv.Close()
	a := &App{ClientID: "c", Key: testKey(t), Repo: "o/r", BaseURL: srv.URL, Now: func() time.Time { return now }}
	ctx := context.Background()

	if b, err := a.FileContent(ctx, ".github/CODEOWNERS", "main"); err != nil || string(b) != "/bot/ @x" {
		t.Errorf("content %q %v", b, err)
	}
	if fs, err := a.PullRequestFiles(ctx, 4); err != nil || strings.Join(fs, ",") != "a,b,c" {
		t.Errorf("files %v %v", fs, err)
	}
	if err := a.UpdateBranch(ctx, 4, "h1"); err != nil || updated["expected_head_sha"] != "h1" {
		t.Errorf("update %v %v", updated, err)
	}
	sha, err := a.SquashMerge(ctx, 4, "h1", "feat: x (#4)", "body")
	if err != nil || sha != "m1" || merged["sha"] != "h1" || merged["merge_method"] != "squash" || merged["commit_title"] != "feat: x (#4)" {
		t.Errorf("merge %v %v %v", sha, merged, err)
	}
	var apiErr *APIError
	if _, err := a.SquashMerge(ctx, 5, "h1", "t", ""); !errors.As(err, &apiErr) || apiErr.Status != http.StatusConflict {
		t.Errorf("want 409, got %v", err)
	}
	if c, err := a.Compare(ctx, "main", "agent/4-x"); err != nil || c.BehindBy != 2 {
		t.Errorf("compare %+v %v", c, err)
	}
}

func TestFilePathsRejectsTruncationAndFiltersTrees(t *testing.T) {
	for _, truncated := range []bool{false, true} {
		t.Run(fmt.Sprint(truncated), func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/repos/o/r/git/trees/deployed" || r.URL.Query().Get("recursive") != "1" {
					t.Errorf("unexpected tree request %s", r.URL)
				}
				fmt.Fprintf(w, `{"truncated":%t,"tree":[{"path":"game","type":"tree"},{"path":"game/features/frogs/release_notes/1-frogs.json","type":"blob"}]}`, truncated)
			}))
			defer srv.Close()
			a := &App{Repo: "o/r", BaseURL: srv.URL, token: "test", tokenExpiry: time.Now().Add(time.Hour)}
			paths, err := a.FilePaths(context.Background(), "deployed")
			if truncated {
				if err == nil {
					t.Fatal("truncated tree accepted")
				}
			} else if err != nil || len(paths) != 1 || paths[0] != "game/features/frogs/release_notes/1-frogs.json" {
				t.Fatalf("paths %q error %v", paths, err)
			}
		})
	}
}
