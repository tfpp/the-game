package discordbot

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/disgoorg/disgo/discord"
	"github.com/tfpp/the-game/bot/internal/claude"
	"github.com/tfpp/the-game/bot/internal/codex"
)

type fakeUsageReporter struct {
	text  string
	err   error
	calls int
}

func (r *fakeUsageReporter) Report(context.Context) (string, error) {
	r.calls++
	return r.text, r.err
}

func TestUsageCombinesProviders(t *testing.T) {
	for _, tt := range []struct {
		name       string
		claudeErr  error
		codexErr   error
		wantClaude string
		wantCodex  string
	}{
		{"both", nil, nil, "Claude success", "Codex success"},
		{"claude unavailable", errors.New("private upstream response"), nil, "Couldn't get usage limits", "Codex success"},
		{"codex unavailable", nil, errors.New("private upstream response"), "Claude success", "Couldn't get usage limits"},
		{"claude unconfigured", claude.ErrNoToken, nil, "Not set up", "Codex success"},
		{"codex unconfigured", nil, codex.ErrNoAuth, "Claude success", "Not set up"},
		{"codex expired", nil, codex.ErrAuthExpired, "Claude success", "Refresh the bot's Codex auth.json login"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			c := &fakeUsageReporter{text: "Claude success", err: tt.claudeErr}
			x := &fakeUsageReporter{text: "Codex success", err: tt.codexErr}
			b := &Bot{Claude: c, Codex: x}
			got := b.usageReport(context.Background())
			if !strings.Contains(got, tt.wantClaude) || !strings.Contains(got, tt.wantCodex) || strings.Contains(got, "private upstream") {
				t.Fatalf("report: %s", got)
			}
			if c.calls != 1 || x.calls != 1 {
				t.Fatalf("one provider hid the other: calls=%d,%d", c.calls, x.calls)
			}
		})
	}
}

func TestUsageMissingProviders(t *testing.T) {
	for _, b := range []*Bot{{}, {Claude: (*claude.Client)(nil), Codex: (*codex.Client)(nil)}} {
		got := b.usageReport(context.Background())
		if strings.Count(got, "Not set up") != 2 {
			t.Fatalf("missing providers: %s", got)
		}
	}
}

func TestUsageCommandDescribesBothProviders(t *testing.T) {
	for _, command := range commands {
		if cmd, ok := command.(discord.SlashCommandCreate); ok && cmd.Name == "usage" {
			if !strings.Contains(cmd.Description, "Claude and Codex") || len(cmd.Options) != 0 {
				t.Fatalf("unexpected usage command: %+v", cmd)
			}
			return
		}
	}
	t.Fatal("usage command missing")
}
