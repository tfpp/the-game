package discordbot

import (
	"context"
	"errors"
	"fmt"

	"github.com/tfpp/the-game/bot/internal/claude"
	"github.com/tfpp/the-game/bot/internal/codex"
)

// UsageReporter renders one provider's subscription limits as Discord Markdown.
type UsageReporter interface {
	Report(context.Context) (string, error)
}

// A provider's missing credentials or upstream failure must not hide the other's
// report. The caller defers ephemerally before making either network request.
func (b *Bot) usageReport(ctx context.Context) string {
	report := func(name string, client UsageReporter) string {
		missing := fmt.Sprintf("**%s usage limits**\nNot set up on this bot.", name)
		if client == nil {
			return missing
		}
		text, err := client.Report(ctx)
		switch {
		case err == nil:
			return text
		case errors.Is(err, claude.ErrNoToken), errors.Is(err, codex.ErrNoAuth):
			return missing
		case errors.Is(err, codex.ErrAuthExpired):
			return "**Codex usage limits**\n⚠️ Login expired or was rejected. Refresh the bot's Codex auth.json login."
		default:
			if b.cfg.Logger != nil {
				b.cfg.Logger.Error("subscription usage failed", "provider", name, "err", err)
			}
			return fmt.Sprintf("**%s usage limits**\n❌ Couldn't get usage limits. Try again later.", name)
		}
	}
	return report("Claude", b.Claude) + "\n\n" + report("Codex", b.Codex)
}
