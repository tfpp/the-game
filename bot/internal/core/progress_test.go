package core

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tfpp/the-game/bot/internal/github"
)

type liveCall struct {
	thread, message string
	edit            bool
	embed           Embed
}

type fakeLive struct {
	mu      sync.Mutex
	calls   []liveCall
	editErr error
}

func (f *fakeLive) PostLive(_ context.Context, thread string, e Embed) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	id := fmt.Sprintf("msg%d", len(f.calls)+1)
	f.calls = append(f.calls, liveCall{thread: thread, message: id, embed: e})
	return id, nil
}

func (f *fakeLive) EditLive(_ context.Context, thread, message string, e Embed) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.editErr != nil {
		return f.editErr
	}
	f.calls = append(f.calls, liveCall{thread: thread, message: message, edit: true, embed: e})
	return nil
}

func (f *fakeLive) snapshot() []liveCall {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]liveCall(nil), f.calls...)
}

func (f *fakeLive) last(t *testing.T) liveCall {
	t.Helper()
	calls := f.snapshot()
	if len(calls) == 0 {
		t.Fatal("nothing posted")
	}
	return calls[len(calls)-1]
}

func text(e Embed) string {
	s := e.Title + "\n" + e.Description
	for _, f := range e.Fields {
		s += "\n" + f.Name + ": " + f.Value
	}
	return s
}

var secret = []byte("progress-secret")

func update(id string, attempt, seq int, events ...ProgressEvent) ProgressUpdate {
	return ProgressUpdate{RequestID: id, Agent: "pi", Model: "openai-codex/gpt-6.1-sol", Seq: seq,
		Attempt: attempt, Attempts: 3, Events: events}
}

func TestProgressToken(t *testing.T) {
	// Must match agent.yml: printf 'agent-progress:%s' bot-7 | openssl dgst -sha256 -hmac s3cret -r
	if got := ProgressToken([]byte("s3cret"), "bot-7"); got != "ab41b1513819af9a22071bb699b921ae04358852ac3e41da46731f7412b9e53f" {
		t.Errorf("token %q", got)
	}
}

func TestProgressLiveMessage(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	live := &fakeLive{}
	p := NewProgress(e.svc, live, secret)
	p.MinEdit = 0
	tok := ProgressToken(secret, "bot-1")

	if err := p.Update(ctx, "nope", update("bot-1", 1, 1)); !errors.Is(err, ErrProgressDenied) {
		t.Errorf("wrong token: %v", err)
	}
	if err := p.Update(ctx, ProgressToken(secret, "bot-2"), update("bot-1", 1, 1)); !errors.Is(err, ErrProgressDenied) {
		t.Errorf("another run's token: %v", err)
	}
	if err := p.Update(ctx, ProgressToken(secret, "bot-99"), update("bot-99", 1, 1)); !errors.Is(err, ErrProgressClosed) {
		t.Errorf("unknown run: %v", err)
	}
	if err := p.Update(ctx, ProgressToken(secret, "x"), update("x", 1, 1)); !errors.Is(err, ErrProgressClosed) {
		t.Errorf("not a bot request: %v", err)
	}

	must(t, p.Update(ctx, tok, update("bot-1", 1, 1)))
	p.Wait()
	first := live.last(t)
	if first.edit || first.thread != "thread1" || !strings.Contains(first.embed.Description, "Starting up") {
		t.Fatalf("first call %+v", first)
	}
	if got, _ := e.st.Get(ctx, "progress:1"); got != first.message {
		t.Errorf("stored message %q", got)
	}

	must(t, p.Update(ctx, tok, update("bot-1", 1, 2,
		ProgressEvent{"reasoning", "**Planning**\n\nLook at the  movement feature."},
		ProgressEvent{"tool", "bash rg --files game/features"},
		ProgressEvent{"text", "never shown"},
		ProgressEvent{"error", "429 overloaded"})))
	must(t, p.Update(ctx, tok, update("bot-1", 1, 2, ProgressEvent{"tool", "repeated batch"})))
	must(t, p.Update(ctx, tok, update("bot-1", 2, 1, ProgressEvent{"tool", "bash harness/verify.sh"})))
	p.Wait()
	got := live.last(t)
	if !got.edit || got.message != first.message {
		t.Fatalf("not an edit of the live message: %+v", got)
	}
	want := "💭 **Planning** Look at the movement feature.\n🔧 `bash rg --files game/features`\n⚠️ 429 overloaded\n" +
		"🔁 **Attempt 2**: fixing what verification found\n🔧 `bash harness/verify.sh`"
	if got.embed.Description != want {
		t.Errorf("description:\n%s\nwant:\n%s", got.embed.Description, want)
	}
	s := text(got.embed)
	for _, w := range []string{"🧠 Agent at work", "Agent: `pi · openai-codex/gpt-6.1-sol`", "Attempt: 2/3",
		"Activity: 1 thought · 2 tool calls", "Updated: <t:1800000000:R>"} {
		if !strings.Contains(s, w) {
			t.Errorf("embed lacks %q:\n%s", w, s)
		}
	}

	// The workflow run completes: the message is marked finished, and updates stop.
	must(t, e.svc.WorkflowRun(ctx, github.WorkflowRun{ID: 900, Path: ".github/workflows/agent.yml",
		DisplayTitle: "agent #11 implement [bot-1]", Status: "completed", Conclusion: "failure", HTMLURL: "https://run"}))
	p.Wait()
	got = live.last(t)
	s = text(got.embed)
	if !got.edit || !strings.Contains(s, "🧠 Agent run finished") || !strings.Contains(s, "Workflow: `failure`") ||
		strings.Contains(s, "Updated") || !strings.Contains(s, "bash harness/verify.sh") {
		t.Errorf("finished embed %+v:\n%s", got, s)
	}
	if err := p.Update(ctx, tok, update("bot-1", 2, 2)); !errors.Is(err, ErrProgressClosed) {
		t.Errorf("update after the run: %v", err)
	}
}

func TestProgressThrottlesEdits(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	live := &fakeLive{}
	p := NewProgress(e.svc, live, secret)
	p.MinEdit = 80 * time.Millisecond
	tok := ProgressToken(secret, "bot-1")

	must(t, p.Update(ctx, tok, update("bot-1", 1, 1)))
	p.Wait()
	for i := 2; i <= 5; i++ {
		must(t, p.Update(ctx, tok, update("bot-1", 1, i, ProgressEvent{"tool", fmt.Sprint("step ", i)})))
	}
	if n := len(live.snapshot()); n != 1 {
		t.Errorf("%d calls before the minimum edit interval", n)
	}
	p.Wait()
	calls := live.snapshot()
	if len(calls) != 2 || !strings.Contains(calls[1].embed.Description, "step 5") {
		t.Errorf("want one combined edit, got %d calls: %+v", len(calls), calls)
	}
}

func TestProgressRestartAndLostMessage(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.feature(t, "42", "add jump pads please")
	must(t, e.st.Set(ctx, "progress:1", "msg-before-restart"))
	live := &fakeLive{}
	p := NewProgress(e.svc, live, secret)
	p.MinEdit = 0
	tok := ProgressToken(secret, "bot-1")

	must(t, p.Update(ctx, tok, update("bot-1", 1, 3, ProgressEvent{"tool", "ls"})))
	p.Wait()
	if got := live.last(t); !got.edit || got.message != "msg-before-restart" {
		t.Errorf("after a restart the saved message is edited: %+v", got)
	}

	// The message was deleted: the next update posts a new one.
	live.editErr = errors.New("unknown message")
	must(t, p.Update(ctx, tok, update("bot-1", 1, 4, ProgressEvent{"tool", "ls -la"})))
	p.Wait()
	live.editErr = nil
	must(t, p.Update(ctx, tok, update("bot-1", 1, 5, ProgressEvent{"tool", "cat a"})))
	p.Wait()
	if got := live.last(t); got.edit || got.message == "msg-before-restart" {
		t.Errorf("want a new message, got %+v", got)
	}
}

func TestProgressRendering(t *testing.T) {
	lr := &liveRun{}
	long := strings.Repeat("x", 500)
	lr.apply(ProgressUpdate{Agent: "evil<@1>", Model: "m`odel <@&2>", Seq: 1, Events: []ProgressEvent{
		{"reasoning", "see [docs](https://evil.example) now"},
		{"reasoning", "**unclosed bold " + long},
		{"tool", "bash echo `id`"},
		{"note", "   "},
		{"unknown", "dropped"},
	}})
	e := lr.embed()
	lines := strings.Split(e.Description, "\n")
	if len(lines) != 3 {
		t.Fatalf("lines %q", lines)
	}
	if lines[0] != "💭 see [docs]\u200b(https://evil.example) now" {
		t.Errorf("masked link not neutralized: %q", lines[0])
	}
	if strings.Contains(lines[1], "**") || !strings.HasSuffix(lines[1], "x…") ||
		len([]rune(lines[1])) != len([]rune("💭 "))+liveLineChars+1-len("**") {
		t.Errorf("clipped reasoning %q", lines[1])
	}
	if lines[2] != "🔧 `bash echo ˋidˋ`" {
		t.Errorf("tool %q", lines[2])
	}
	if f := e.Fields[0]; f.Value != "`agent · model2`" {
		t.Errorf("agent field %q", f.Value)
	}

	for i := range 200 {
		lr.apply(ProgressUpdate{Seq: i + 2, Events: []ProgressEvent{{"reasoning", fmt.Sprint(i, " ", long)}}})
	}
	e = lr.embed()
	if len(lr.lines) != liveLines || len([]rune(e.Description)) > maxDescription ||
		!strings.HasPrefix(e.Description, "…\n") || !strings.HasSuffix(e.Description, "x…") ||
		!strings.Contains(e.Description, "💭 199 ") {
		t.Errorf("tail: %d lines, %d chars:\n%s", len(lr.lines), len([]rune(e.Description)), e.Description)
	}
}
