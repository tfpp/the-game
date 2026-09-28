package core

import (
	"context"
	"strings"
	"testing"

	"github.com/tfpp/the-game/bot/internal/store"
)

func TestFeatureRequiresSupportedHarness(t *testing.T) {
	for _, harness := range []string{"", "pi", "Codex", "unknown"} {
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
	for _, harness := range []string{"claude", "codex"} {
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
