package discordbot

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/disgoorg/disgo/discord"
	"github.com/tfpp/the-game/bot/internal/profile"
)

type fakeProfiles struct {
	p    profile.Profile
	err  error
	user string
}

func (f *fakeProfiles) Lookup(_ context.Context, user string) (profile.Profile, error) {
	f.user = user
	return f.p, f.err
}

func TestProfileCommand(t *testing.T) {
	for _, command := range commands {
		cmd := command.(discord.SlashCommandCreate)
		if cmd.Name != "profile" {
			continue
		}
		if len(cmd.Contexts) != 1 || cmd.Contexts[0] != discord.InteractionContextTypeGuild || len(cmd.Options) != 1 {
			t.Fatal(cmd)
		}
		opt, ok := cmd.Options[0].(discord.ApplicationCommandOptionUser)
		if !ok || !opt.Required || opt.Name != "user" {
			t.Fatal(cmd.Options)
		}
		return
	}
	t.Fatal("profile not registered")
}

func TestProfileReport(t *testing.T) {
	b := &Bot{}
	if text := b.profileReport(context.Background(), "123"); !strings.Contains(text, "aren't set up") {
		t.Fatal(text)
	}
	f := &fakeProfiles{p: profile.Profile{DisplayName: "Gamer", PlaytimeSeconds: 90061}}
	b.Profiles = f
	text := b.profileReport(context.Background(), "123")
	if f.user != "123" || !strings.Contains(text, "25h 1m 1s") || !strings.Contains(text, "`Gamer`") {
		t.Fatal(text, f)
	}
	f.p = profile.Profile{}
	if text := b.profileReport(context.Background(), "123"); !strings.Contains(text, "Name not chosen") || !strings.Contains(text, "0h 0m 0s") {
		t.Fatal(text)
	}
	f.p.DisplayName = "@everyone`\nforged"
	if text := b.profileReport(context.Background(), "123"); strings.Contains(text, "@everyone") || strings.Contains(text, "\nforged") {
		t.Fatal(text)
	}
	f.err = profile.ErrNotFound
	if text := b.profileReport(context.Background(), "123"); !strings.Contains(text, "link Discord") {
		t.Fatal(text)
	}
	f.err = errors.New("private upstream failure")
	if text := b.profileReport(context.Background(), "123"); strings.Contains(text, "private") || !strings.Contains(text, "Try again") {
		t.Fatal(text)
	}
}
