package discordbot

import (
	"testing"

	"github.com/disgoorg/disgo/discord"
)

func TestFeatureRequiresHarnessChoice(t *testing.T) {
	for _, command := range commands {
		cmd, ok := command.(discord.SlashCommandCreate)
		if !ok || cmd.Name != "feature" {
			continue
		}
		for _, option := range cmd.Options {
			opt, ok := option.(discord.ApplicationCommandOptionString)
			if !ok || opt.Name != "harness" {
				continue
			}
			if !opt.Required || len(opt.Choices) != 2 {
				t.Fatalf("harness must be required with two choices: %+v", opt)
			}
			for i, value := range []string{"claude", "codex"} {
				if opt.Choices[i].Value != value || opt.Choices[i].Name != value {
					t.Fatalf("unexpected choice: %+v", opt.Choices[i])
				}
			}
			return
		}
		t.Fatal("feature has no harness option")
	}
	t.Fatal("feature command not registered")
}
