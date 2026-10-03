package discordbot

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"unicode"

	"github.com/tfpp/the-game/bot/internal/profile"
)

type ProfileLookup interface {
	Lookup(context.Context, string) (profile.Profile, error)
}

func (b *Bot) profileReport(ctx context.Context, user string) string {
	if b.Profiles == nil {
		return "Player profiles aren't set up on this bot yet."
	}
	p, err := b.Profiles.Lookup(ctx, user)
	if errors.Is(err, profile.ErrNotFound) {
		return "No linked game profile for that user. Sign in with Discord in the game, or link Discord from the account screen."
	}
	if err != nil {
		return "Couldn't look up that profile. Try again later."
	}
	name := strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || r == '`' || r == '@' {
			return ' '
		}
		return r
	}, p.DisplayName)
	if strings.TrimSpace(name) == "" {
		name = "Name not chosen yet"
	}
	return fmt.Sprintf("**Game profile**\nName: `%s`\nRecorded playtime: **%dh %dm %ds**\nCounts connected game time since this update; excludes offline previews.",
		name, p.PlaytimeSeconds/3600, p.PlaytimeSeconds/60%60, p.PlaytimeSeconds%60)
}
