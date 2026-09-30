package core

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/tfpp/the-game/bot/internal/store"
)

func TestFeatureRequiresSupportedHarness(t *testing.T) {
	for _, harness := range []string{"", "Pi", "Codex", "unknown"} {
		t.Run(harness, func(t *testing.T) {
			e := newEnv(t)
			r := e.feature(t, "42", "add jump pads please", harness)
			if !strings.Contains(r.rejected, "Choose a harness") || r.deferred {
				t.Fatalf("invalid harness accepted: %+v", r)
			}
			if len(e.gh.issues) != 0 || len(e.gh.dispatches) != 0 {
				t.Fatal("invalid harness created a GitHub issue or dispatch")
			}
			runs, err := e.st.ActiveRuns(context.Background())
			must(t, err)
			if len(runs) != 0 {
				t.Fatal("invalid harness consumed an agent slot")
			}
		})
	}
}

func TestFeatureDispatchesSelectedHarness(t *testing.T) {
	for _, harness := range []string{"claude", "codex", "pi"} {
		t.Run(harness, func(t *testing.T) {
			e := newEnv(t)
			e.svc.cfg.Agent = "codex"
			if harness == "codex" {
				e.svc.cfg.Agent = "claude"
			}
			r := e.feature(t, "42", "add jump pads please", harness)
			if r.rejected != "" || len(e.gh.dispatches) != 1 {
				t.Fatalf("feature failed: %+v", r)
			}
			if d := e.gh.dispatches[0]; d["agent"] != harness {
				t.Fatalf("dispatch ignored selected harness: %v", d)
			}
			job, err := e.st.JobByThread(context.Background(), "thread1")
			must(t, err)
			if job.Harness != harness || !strings.Contains(r.response, "harness: `"+harness+"`") {
				t.Fatalf("selection not saved/shown: job=%+v response=%s", job, r.response)
			}
		})
	}
}

func TestQueuedFeaturesKeepHarnessAfterServiceRestart(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	e.svc.cfg.Limits.MaxActive = 1
	e.feature(t, "1", "occupy the agent slot", "claude")
	e.feature(t, "2", "queued codex feature", "codex")
	e.feature(t, "3", "queued claude feature", "claude")
	if len(e.gh.dispatches) != 1 {
		t.Fatalf("dispatches %v", e.gh.dispatches)
	}
	for i, harness := range []string{"codex", "claude"} {
		// A new service has no in-memory request information. Even a changed global
		// default must not change the harness stored with either queued feature.
		cfg := e.svc.cfg
		cfg.Agent = "claude"
		if harness == "claude" {
			cfg.Agent = "codex"
		}
		e.svc = New(cfg, e.st, e.gh, e.chat)
		must(t, e.st.SetRunStatus(ctx, int64(i+1), store.RunCompleted, "success", 0, "", e.now))
		e.svc.drain(ctx)
		if len(e.gh.dispatches) != i+2 || e.gh.dispatches[i+1]["agent"] != harness {
			t.Fatalf("queued harness changed: %v", e.gh.dispatches)
		}
	}
}

func TestLegacyJobUsesConfiguredHarness(t *testing.T) {
	for _, fallback := range []string{"", "claude", "codex"} {
		t.Run(fallback, func(t *testing.T) {
			e := newEnv(t)
			ctx := context.Background()
			e.svc.cfg.Agent = fallback
			run, err := e.svc.reserve(ctx, "42", 0, "implement", "")
			must(t, err)
			job, err := e.st.CreateJob(ctx, store.Job{Issue: 11, Title: "legacy request", RequesterID: "42"}, run.ID, e.now)
			must(t, err)
			run.JobID = job.ID
			must(t, e.svc.dispatch(ctx, run, job.Issue, ""))
			want := fallback
			if want == "" {
				want = "claude"
			}
			if e.gh.dispatches[0]["agent"] != want {
				t.Fatalf("legacy dispatch %v", e.gh.dispatches[0])
			}
		})
	}
}

func (e *env) featureWithModel(t *testing.T, user, text, harness, model string) *fakeResponder {
	t.Helper()
	r := &fakeResponder{counter: &e.nth}
	err := e.svc.Feature(context.Background(), FeatureRequest{
		UserID: user, UserName: "Al@ice*", HasRole: true, ChannelID: "c1", Text: text,
		Harness: harness, Model: model,
	}, r)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestFeatureRejectsInvalidModel(t *testing.T) {
	cases := []struct{ harness, model, reason string }{
		{"claude", "openrouter/z-ai/glm-5.3", "Only the pi harness takes a model"},
		{"codex", "openai-codex/gpt-6.1-sol", "Only the pi harness takes a model"},
		{"pi", "openrouter/unknown/model", "Choose one of the offered pi models"},
	}
	for _, c := range cases {
		t.Run(c.harness+" "+c.model, func(t *testing.T) {
			e := newEnv(t)
			r := e.featureWithModel(t, "42", "add jump pads please", c.harness, c.model)
			if !strings.Contains(r.rejected, c.reason) || r.deferred {
				t.Fatalf("invalid model accepted: %+v", r)
			}
			if len(e.gh.issues) != 0 || len(e.gh.dispatches) != 0 {
				t.Fatal("invalid model created a GitHub issue or dispatch")
			}
		})
	}
}

func TestPiModelIsSavedAndDispatchedOnEveryRun(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()
	model := "openrouter/moonshotai/kimi-k3"
	r := e.featureWithModel(t, "42", "add jump pads please", "pi", model)
	if r.rejected != "" || len(e.gh.dispatches) != 1 {
		t.Fatalf("feature failed: %+v", r)
	}
	if d := e.gh.dispatches[0]; d["agent"] != "pi" || d["pi_model"] != model {
		t.Fatalf("dispatch %v", d)
	}
	if !strings.Contains(r.response, "harness: `pi` · model: `"+model+"`") {
		t.Fatalf("model not announced: %s", r.response)
	}
	job, err := e.st.JobByThread(ctx, "thread1")
	must(t, err)
	if job.Harness != "pi" || job.Model != model {
		t.Fatalf("job %+v", job)
	}
	// A later run (a revision after a restart, say) resolves the model from the job.
	e.svc = New(e.svc.cfg, e.st, e.gh, e.chat)
	run, err := e.svc.reserve(ctx, "42", job.ID, "revise", "tweak it")
	must(t, err)
	must(t, e.svc.dispatch(ctx, run, job.Issue, "tweak it"))
	if d := e.gh.dispatches[len(e.gh.dispatches)-1]; d["agent"] != "pi" || d["pi_model"] != model || d["mode"] != "revise" {
		t.Fatalf("revision dispatch %v", d)
	}
}

func TestPiModelIsOptionalAndOnlySentForPi(t *testing.T) {
	for _, harness := range []string{"pi", "claude", "codex"} {
		t.Run(harness, func(t *testing.T) {
			e := newEnv(t)
			r := e.featureWithModel(t, "42", "add jump pads please", harness, "")
			if r.rejected != "" || len(e.gh.dispatches) != 1 {
				t.Fatalf("feature failed: %+v", r)
			}
			// No pi_model: the workflow picks its default, and older workflows without
			// the input keep accepting claude and codex dispatches.
			if _, ok := e.gh.dispatches[0]["pi_model"]; ok {
				t.Fatalf("unexpected pi_model: %v", e.gh.dispatches[0])
			}
			if strings.Contains(r.response, "model:") {
				t.Fatalf("empty model announced: %s", r.response)
			}
		})
	}
}

// The bot must only offer models the agent workflow accepts.
func TestPiModelsMatchWorkflowChoices(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("..", "..", "..", ".github", "workflows", "agent.yml"))
	must(t, err)
	var choices []string
	in, options := false, false
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		switch {
		case trimmed == "pi_model:":
			in = true
		case in && trimmed == "options:":
			options = true
		case in && options && strings.HasPrefix(trimmed, "- "):
			choices = append(choices, strings.TrimPrefix(trimmed, "- "))
		case in && options:
			in, options = false, false
		}
	}
	var want []string
	for _, m := range PiModels {
		want = append(want, m.ID)
	}
	if len(choices) == 0 || choices[0] != "default" || !slices.Equal(choices[1:], want) {
		t.Fatalf("agent.yml pi_model choices %v; bot offers %v", choices, want)
	}
}
