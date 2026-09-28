// Package discordbot connects the core service to Discord through the gateway: it
// registers the slash commands in one guild, routes them to core, and posts to threads.
package discordbot

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"time"

	"github.com/disgoorg/disgo"
	"github.com/disgoorg/disgo/bot"
	"github.com/disgoorg/disgo/cache"
	"github.com/disgoorg/disgo/discord"
	"github.com/disgoorg/disgo/events"
	"github.com/disgoorg/disgo/gateway"
	"github.com/disgoorg/disgo/rest"
	"github.com/disgoorg/snowflake/v2"

	"github.com/tfpp/the-game/bot/internal/claude"
	"github.com/tfpp/the-game/bot/internal/core"
)

// Config selects the guild, the role allowed to request features, the role allowed to
// approve merges, and optionally the only channel /feature works in.
type Config struct {
	Token            string
	GuildID          snowflake.ID
	RequesterRoleID  snowflake.ID
	ApproverRoleID   snowflake.ID // 0: nobody can approve from Discord
	FeatureChannelID snowflake.ID // 0: any text channel
	Logger           *slog.Logger
}

// Bot is the Discord side of the bot. Set Service (and optionally Claude) before Open.
type Bot struct {
	cfg     Config
	client  *bot.Client
	Service *core.Service
	Claude  *claude.Client // nil: /usage says it isn't set up
}

// noMentions is the default: messages never ping anyone unless a call allows it.
var noMentions = discord.AllowedMentions{Parse: []discord.AllowedMentionType{}}

func New(cfg Config) (*Bot, error) {
	b := &Bot{cfg: cfg}
	client, err := disgo.New(cfg.Token,
		bot.WithLogger(cfg.Logger),
		// Interactions arrive regardless of intents; nothing else is needed.
		bot.WithGatewayConfigOpts(gateway.WithIntents(gateway.IntentsNone)),
		bot.WithCacheConfigOpts(cache.WithCaches(cache.FlagsNone)),
		bot.WithRestConfigOpts(rest.WithDefaultAllowedMentions(noMentions)),
		// Commands call GitHub, so they must not block the gateway's read loop.
		bot.WithEventManagerConfigOpts(bot.WithAsyncEventsEnabled()),
		bot.WithEventListenerFunc(b.onCommand),
		bot.WithEventListenerFunc(b.onComponent),
	)
	if err != nil {
		return nil, err
	}
	b.client = client
	return b, nil
}

var (
	minLen, maxLen = 10, 1500
	commands       = []discord.ApplicationCommandCreate{
		discord.SlashCommandCreate{
			Name:        "feature",
			Description: "Ask the agent to build a feature for the game",
			Contexts:    []discord.InteractionContextType{discord.InteractionContextTypeGuild},
			Options: []discord.ApplicationCommandOption{
				discord.ApplicationCommandOptionString{
					Name: "request", Description: "What should it do?", Required: true,
					MinLength: &minLen, MaxLength: &maxLen,
				},
				discord.ApplicationCommandOptionString{
					Name: "harness", Description: "Which coding harness should build and revise this feature?", Required: true,
					Choices: []discord.ApplicationCommandOptionChoiceString{
						{Name: "claude", Value: "claude"},
						{Name: "codex", Value: "codex"},
					},
				},
			},
		},
		discord.SlashCommandCreate{
			Name:        "revise",
			Description: "Ask the agent to change this thread's PR",
			Contexts:    []discord.InteractionContextType{discord.InteractionContextTypeGuild},
			Options: []discord.ApplicationCommandOption{discord.ApplicationCommandOptionString{
				Name: "changes", Description: "What should change?", Required: true, MaxLength: &maxLen,
			}},
		},
		discord.SlashCommandCreate{
			Name:        "approve",
			Description: "Approve this thread's PR at its latest commit and queue it for merging",
			Contexts:    []discord.InteractionContextType{discord.InteractionContextTypeGuild},
		},
		discord.SlashCommandCreate{
			Name:        "close",
			Description: "Close this thread's PR and issue without merging",
			Contexts:    []discord.InteractionContextType{discord.InteractionContextTypeGuild},
		},
		discord.SlashCommandCreate{
			Name:        "queue",
			Description: "Show the agent runs or the merge queue",
			Contexts:    []discord.InteractionContextType{discord.InteractionContextTypeGuild},
			Options: []discord.ApplicationCommandOption{discord.ApplicationCommandOptionString{
				Name: "which", Description: "Which queue", Required: true,
				Choices: []discord.ApplicationCommandOptionChoiceString{
					{Name: "agent runs", Value: "agent"},
					{Name: "merge queue", Value: "merge"},
				},
			}},
		},
		discord.SlashCommandCreate{
			Name:        "usage",
			Description: "Show how much of Claude's usage limits the agent has used",
			Contexts:    []discord.InteractionContextType{discord.InteractionContextTypeGuild},
		},
	}
)

// Open registers the guild commands and connects to the gateway.
func (b *Bot) Open(ctx context.Context) error {
	if _, err := b.client.Rest.SetGuildCommands(b.client.ApplicationID, b.cfg.GuildID, commands); err != nil {
		return fmt.Errorf("register commands: %w", err)
	}
	return b.client.OpenGateway(ctx)
}

func (b *Bot) Close(ctx context.Context) { b.client.Close(ctx) }

// Ready reports whether the gateway connection is up.
func (b *Bot) Ready() bool {
	return b.client.Gateway != nil && b.client.Gateway.Status() == gateway.StatusReady
}

// Post implements core.Chat.
func (b *Bot) Post(ctx context.Context, threadID, content string, ping ...string) error {
	id, err := snowflake.Parse(threadID)
	if err != nil {
		return err
	}
	_, err = b.client.Rest.CreateMessage(id, discord.MessageCreate{
		Content: content, AllowedMentions: mentions(ping),
	}, rest.WithCtx(ctx))
	return err
}

// PostButton implements core.Chat.
func (b *Bot) PostButton(ctx context.Context, threadID, content, label, id string) error {
	ch, err := snowflake.Parse(threadID)
	if err != nil {
		return err
	}
	_, err = b.client.Rest.CreateMessage(ch, discord.MessageCreate{
		Content:         content,
		AllowedMentions: &noMentions,
		Components:      []discord.LayoutComponent{discord.NewActionRow(discord.NewSuccessButton(label, id))},
	}, rest.WithCtx(ctx))
	return err
}

func mentions(users []string) *discord.AllowedMentions {
	am := noMentions
	for _, u := range users {
		if id, err := snowflake.Parse(u); err == nil {
			am.Users = append(am.Users, id)
		}
	}
	return &am
}

func (b *Bot) onCommand(e *events.ApplicationCommandInteractionCreate) {
	data := e.SlashCommandInteractionData()
	gid := e.GuildID()
	if gid == nil || *gid != b.cfg.GuildID || b.Service == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	member := e.Member()
	if member == nil {
		return
	}
	hasRole := slices.Contains(member.RoleIDs, b.cfg.RequesterRoleID)
	name := member.EffectiveName()
	r := &responder{client: b.client, e: e}
	private := &responder{client: b.client, e: e, ephemeral: true}
	ch := e.Channel()
	var err error
	switch data.CommandName() {
	case "feature":
		switch {
		case b.cfg.FeatureChannelID != 0 && ch.ID() != b.cfg.FeatureChannelID:
			err = r.Reject(ctx, fmt.Sprintf("Use `/feature` in <#%s>.", b.cfg.FeatureChannelID))
		case ch.Type() != discord.ChannelTypeGuildText:
			err = r.Reject(ctx, "Use `/feature` in a text channel, not a thread.")
		default:
			err = b.Service.Feature(ctx, core.FeatureRequest{
				UserID: member.User.ID.String(), UserName: name, HasRole: hasRole,
				ChannelID: ch.ID().String(), Text: data.String("request"), Harness: data.String("harness"),
			}, r)
		}
	case "revise":
		err = b.Service.Revise(ctx, core.ReviseRequest{
			UserID: member.User.ID.String(), UserName: name, HasRole: hasRole,
			ThreadID: ch.ID().String(), Text: data.String("changes"),
		}, r)
	case "approve":
		r = private
		err = b.Service.Approve(ctx, b.approveRequest(member, ch.ID(), ""), r)
	case "close":
		err = b.Service.Close(ctx, core.CloseRequest{
			UserID: member.User.ID.String(), UserName: name, ThreadID: ch.ID().String(),
			HasRole: hasRole || (b.cfg.ApproverRoleID != 0 && slices.Contains(member.RoleIDs, b.cfg.ApproverRoleID)),
		}, r)
	case "queue":
		var text string
		if text, err = b.Service.Queue(ctx, data.String("which")); err == nil {
			err = r.Reject(ctx, text) // private
		}
	case "usage":
		r = private
		if err = r.Defer(ctx); err != nil {
			break
		}
		text, uerr := b.Claude.Report(ctx)
		switch {
		case errors.Is(uerr, claude.ErrNoToken):
			text = "Claude usage isn't set up on this bot."
		case uerr != nil:
			b.cfg.Logger.Error("claude usage failed", "err", uerr)
			text = "❌ Couldn't get Claude's usage limits. Try again later."
		}
		err = r.Respond(ctx, text)
	default:
		return
	}
	if err != nil {
		b.cfg.Logger.Error("command failed", "command", data.CommandName(), "err", err)
		r.fail(ctx)
	}
}

func (b *Bot) approveRequest(member *discord.ResolvedMember, channel snowflake.ID, button string) core.ApproveRequest {
	return core.ApproveRequest{
		UserID: member.User.ID.String(), UserName: member.EffectiveName(), ThreadID: channel.String(),
		HasRole:  b.cfg.ApproverRoleID != 0 && slices.Contains(member.RoleIDs, b.cfg.ApproverRoleID),
		ButtonID: button,
	}
}

func (b *Bot) onComponent(e *events.ComponentInteractionCreate) {
	gid := e.GuildID()
	if gid == nil || *gid != b.cfg.GuildID || b.Service == nil || e.Data.Type() != discord.ComponentTypeButton {
		return
	}
	id := e.ButtonInteractionData().CustomID()
	member := e.Member()
	if member == nil || !core.IsApproveButton(id) {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	r := &responder{client: b.client, e: e, ephemeral: true}
	if err := b.Service.Approve(ctx, b.approveRequest(member, e.Channel().ID(), id), r); err != nil {
		b.cfg.Logger.Error("approve failed", "err", err)
		r.fail(ctx)
	}
}

// interaction is what a responder needs from a command or component interaction.
type interaction interface {
	ApplicationID() snowflake.ID
	Token() string
	CreateMessage(discord.MessageCreate, ...rest.RequestOpt) error
	DeferCreateMessage(bool, ...rest.RequestOpt) error
}

// responder implements core.Responder for one interaction. An ephemeral responder's
// deferred answer is private too.
type responder struct {
	client    *bot.Client
	e         interaction
	ephemeral bool
	deferred  bool
	responded bool
}

func (r *responder) fail(ctx context.Context) {
	if !r.deferred {
		r.Reject(ctx, "Something went wrong. Try again later.")
	} else if !r.responded {
		r.Respond(ctx, "❌ Something went wrong. Try again later.")
	}
}

func (r *responder) Reject(ctx context.Context, msg string) error {
	return r.e.CreateMessage(discord.MessageCreate{
		Content: msg, Flags: discord.MessageFlagEphemeral, AllowedMentions: &noMentions,
	}, rest.WithCtx(ctx))
}

func (r *responder) Defer(ctx context.Context) error {
	if err := r.e.DeferCreateMessage(r.ephemeral, rest.WithCtx(ctx)); err != nil {
		return err
	}
	r.deferred = true
	return nil
}

func (r *responder) Respond(ctx context.Context, content string) error {
	if !r.deferred {
		return errors.New("respond before defer")
	}
	_, err := r.client.Rest.UpdateInteractionResponse(r.e.ApplicationID(), r.e.Token(),
		discord.MessageUpdate{Content: &content, AllowedMentions: &noMentions}, rest.WithCtx(ctx))
	if err == nil {
		r.responded = true
	}
	return err
}

func (r *responder) Thread(ctx context.Context, name string) (string, error) {
	msg, err := r.client.Rest.GetInteractionResponse(r.e.ApplicationID(), r.e.Token(), rest.WithCtx(ctx))
	if err != nil {
		return "", err
	}
	th, err := r.client.Rest.CreateThreadFromMessage(msg.ChannelID, msg.ID, discord.ThreadCreateFromMessage{
		Name: name, AutoArchiveDuration: discord.AutoArchiveDuration1w,
	}, rest.WithCtx(ctx))
	if err != nil {
		return "", err
	}
	return th.ID().String(), nil
}
