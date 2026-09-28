package core

import (
	"strings"
	"testing"
)

const testUsage = " · Model(s): gpt-6-astra · Tokens used: 1397530 · Estimated cost (USD API-equivalent): $2.44"

func TestCompactTokens(t *testing.T) {
	for in, want := range map[string]string{
		"0": "0", "999": "999", "1000": "1K", "1049": "1K", "1050": "1.1K", "42000": "42K",
		"999949": "999.9K", "999950": "1M", "1397530": "1.4M", "12000000": "12M",
		"2500000000": "2.5B", "unavailable": "unavailable", "-5": "-5",
	} {
		if got := compactTokens(in); got != want {
			t.Errorf("compactTokens(%s) = %s, want %s", in, got, want)
		}
	}
}

func fields(e Embed) map[string]string {
	m := map[string]string{}
	for _, f := range e.Fields {
		m[f.Name] = f.Value
	}
	return m
}

func TestRelayEmbedOpened(t *testing.T) {
	e := relayEmbed("🤖 Opened https://github.com/o/r/pull/150"+testUsage+"\n", "https://c")
	if e.Title != "📬 PR #150 opened" || e.URL != "https://github.com/o/r/pull/150" || e.Color != colorSuccess || e.Description != "" {
		t.Errorf("embed %+v", e)
	}
	if f := fields(e); f["Model"] != "gpt-6-astra" || f["Tokens"] != "1.4M" || f["Est. cost (API)"] != "$2.44" {
		t.Errorf("fields %v", f)
	}
}

func TestRelayEmbedStarted(t *testing.T) {
	e := relayEmbed("🤖 Starting `codex` (`implement`) on `agent/146-add-a-craps-table`. [Follow the run](https://run/1).", "https://c")
	if e.Title != "🤖 Agent started" || e.URL != "https://run/1" || e.Color != colorInfo {
		t.Errorf("embed %+v", e)
	}
	if f := fields(e); f["Harness"] != "`codex`" || f["Mode"] != "`implement`" || f["Branch"] != "`agent/146-add-a-craps-table`" {
		t.Errorf("fields %v", f)
	}
}

func TestRelayEmbedPushedKeepsUsageBeforeLongSummary(t *testing.T) {
	body := "🤖 Pushed abcdef0123 https://github.com/o/r/pull/123" + testUsage + "\n\n**fix: red pads**\n\n" + strings.Repeat("summary ", 600)
	e := relayEmbed(body, "https://github.com/o/r/pull/123#issuecomment-456")
	if e.Title != "⬆️ Pushed to PR #123" || e.URL != "https://github.com/o/r/pull/123" || !strings.HasPrefix(e.Description, "**fix: red pads**") {
		t.Errorf("embed %+v", e)
	}
	if f := fields(e); f["Commit"] != "`abcdef0`" || f["Tokens"] != "1.4M" {
		t.Errorf("fields %v", f)
	}
	if !strings.HasSuffix(e.Description, "[More on GitHub](https://github.com/o/r/pull/123#issuecomment-456)") || len([]rune(e.Description)) > 4096 {
		t.Errorf("description not bounded: %d runes", len([]rune(e.Description)))
	}
}

func TestRelayEmbedFailure(t *testing.T) {
	body := "🤖 `codex` (`implement`) did not produce a change: the agent job was cancelled before it finished ([run](https://run/1))\n<details>log</details>"
	e := relayEmbed(body, "https://c")
	if e.Title != "❌ The agent run failed" || e.Color != colorFailure || len(e.Fields) != 0 {
		t.Errorf("embed %+v", e)
	}
	want := "`codex` (`implement`) did not produce a change: the agent job was cancelled before it finished ([run](https://run/1))\n\n[Logs on GitHub](https://c)"
	if e.Description != want {
		t.Errorf("description %q", e.Description)
	}
}

func TestRelayEmbedOtherKinds(t *testing.T) {
	for body, title := range map[string]string{
		"🤖 `claude` (`revise`) made no changes ([run](https://run)" + testUsage + ").\n\nToo vague.": "🤷 The agent made no changes",
		"🤖 Not starting the agent: branch exists":                                                    "⛔ The agent didn't start",
		"🤖 Something new: see https://github.com/o/r/pull/7":                                         "🤖 Agent update",
	} {
		e := relayEmbed(body, "https://c")
		if e.Title != title || strings.HasPrefix(e.Description, "🤖") || strings.Contains(e.Description, "Tokens used") {
			t.Errorf("%q: %+v", body, e)
		}
	}
	if e := relayEmbed("🤖 Something new: see https://github.com/o/r/pull/7", "https://c"); e.Description != "Something new: see [PR #7](https://github.com/o/r/pull/7)" {
		t.Errorf("links: %q", e.Description)
	}
}
