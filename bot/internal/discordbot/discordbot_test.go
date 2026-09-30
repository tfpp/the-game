package discordbot

import (
	"testing"

	"github.com/disgoorg/disgo/discord"
	"github.com/tfpp/the-game/bot/internal/core"
)

func featureOption(t *testing.T, name string) discord.ApplicationCommandOptionString {
	t.Helper()
	for _, command := range commands {
		cmd, ok := command.(discord.SlashCommandCreate)
		if !ok || cmd.Name != "feature" {
			continue
		}
		for _, option := range cmd.Options {
			if opt, ok := option.(discord.ApplicationCommandOptionString); ok && opt.Name == name {
				return opt
			}
		}
		t.Fatalf("feature has no %s option", name)
	}
	t.Fatal("feature command not registered")
	return discord.ApplicationCommandOptionString{}
}

func TestFeatureOffersHarnessesWithPiFirst(t *testing.T) {
	opt := featureOption(t, "harness")
	want := []string{core.DefaultHarness, "claude", "codex"}
	if opt.Required || len(opt.Choices) != len(want) {
		t.Fatalf("harness must be optional (pi by default) with %d choices: %+v", len(want), opt)
	}
	for i, value := range want {
		if opt.Choices[i].Value != value || opt.Choices[i].Name != value {
			t.Fatalf("unexpected choice: %+v", opt.Choices[i])
		}
	}
}

func TestFeatureOffersOptionalPiModels(t *testing.T) {
	opt := featureOption(t, "model")
	if opt.Required || len(opt.Choices) != len(core.PiModels) || len(opt.Choices) > 25 {
		t.Fatalf("model must be optional with every pi model: %+v", opt)
	}
	for i, m := range core.PiModels {
		c := opt.Choices[i]
		if c.Value != m.ID || c.Name != m.Name || len(c.Name) > 100 || len(c.Value) > 100 {
			t.Fatalf("choice %d = %+v; want %+v", i, c, m)
		}
	}
}

func TestFeatureOffersOptionalReasoning(t *testing.T) {
	opt := featureOption(t, "reasoning")
	if opt.Required || len(opt.Choices) != len(core.ReasoningLevels) {
		t.Fatalf("reasoning must be optional with every level: %+v", opt)
	}
	for i, level := range core.ReasoningLevels {
		if c := opt.Choices[i]; c.Value != level || c.Name != level {
			t.Fatalf("choice %d = %+v; want %s", i, c, level)
		}
	}
	if len(opt.Description) > 100 {
		t.Fatalf("description too long for Discord: %d", len(opt.Description))
	}
}
