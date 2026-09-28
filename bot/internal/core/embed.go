package core

import (
	"context"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"

	"github.com/tfpp/the-game/bot/internal/store"
)

// Embed is a Discord embed: a coloured card under a message's content.
type Embed struct {
	Title       string
	URL         string
	Description string
	Color       int
	Fields      []EmbedField
}

// EmbedField is one name/value pair in an embed; inline ones sit side by side.
type EmbedField struct {
	Name, Value string
	Inline      bool
}

// Button is a message button whose custom ID reaches the Discord adapter when pressed.
type Button struct{ Label, ID string }

// Embed colours, from Discord's palette.
const (
	colorInfo    = 0x5865F2 // blurple: started
	colorSuccess = 0x57F287 // green: opened, pushed
	colorWarning = 0xFEE75C // yellow: no changes
	colorFailure = 0xED4245 // red: failed, refused
	colorNeutral = 0x99AAB5 // grey: anything else
)

// Limits below Discord's (4096 description, 1024 field value) leave room for links.
const (
	maxDescription = 3000
	maxFieldValue  = 200
)

// postEmbed writes an embed to a job's thread, if it has one. content carries the pings,
// which embeds can't. Errors are logged, like post.
func (s *Service) postEmbed(ctx context.Context, jobThread string, issue int, embed Embed, button *Button, ping ...string) {
	if jobThread == "" {
		return
	}
	var content string
	for _, id := range ping {
		content += "<@" + id + "> "
	}
	if err := s.chat.PostEmbed(ctx, jobThread, strings.TrimSpace(content), embed, button, ping...); err != nil {
		s.log.Error("post embed to thread", "err", err, "issue", issue)
	}
}

// reviseHint tells the requester how to ask for changes once the PR exists.
const reviseHint = "Once the PR is open, use `/revise` in this thread to ask for changes."

// card posts an embed to a job's thread, if it has one, pinging ping.
func (s *Service) card(ctx context.Context, job store.Job, e Embed, ping ...string) {
	s.postEmbed(ctx, job.ThreadID, job.Issue, e, nil, ping...)
}

// resolvingCard says the agent has started resolving a PR's conflicts.
func (s *Service) resolvingCard(ctx context.Context, job store.Job) {
	s.card(ctx, job, Embed{Title: "🔧 Resolving conflicts", URL: s.pullURL(job.PR), Color: colorInfo, Description: fmt.Sprintf(
		"The agent is merging `%s` into %s and resolving the conflicts.", s.cfg.Ref, s.prLabel(job.PR))})
}

func (s *Service) pullURL(n int) string {
	return fmt.Sprintf("https://github.com/%s/pull/%d", s.cfg.Repo, n)
}

// prLabel names PR n in an embed's description; the embed's title links to it.
func (s *Service) prLabel(n int) string { return fmt.Sprintf("PR #%d", n) }

var (
	// harness/publish.sh's per-run usage note.
	// Older notes have no Reasoning part.
	usageNote = regexp.MustCompile(` · Model\(s\): ([^·\n]+?)(?: · Reasoning: ([^·\s)]+))? · Tokens used: ([^·\s)]+) · Estimated cost \(USD API-equivalent\): ([^\s)]+)`)
	startedRe = regexp.MustCompile("^Starting `([^`]+)` \\(`([^`]+)`\\) on `([^`]+)`\\. \\[Follow the run\\]\\(([^)\\s]+)\\)\\.?$")
	openedRe  = regexp.MustCompile(`^Opened (https://github\.com/\S+/pull/(\d+))\s*$`)
	pushedRe  = regexp.MustCompile(`^Pushed ([0-9a-f]+) (https://github\.com/\S+/pull/(\d+))\s*`)
	// Masked links in embeds don't need, and may not render, the <…> that stops previews.
	anglePreview = regexp.MustCompile(`\]\(<([^<>\s]+)>\)`)
)

// relayEmbed turns a harness 🤖 comment into an embed: a title and colour for its kind,
// the text without collapsed logs, and the run's usage as fields.
func relayEmbed(body, url string) Embed {
	body = strings.ReplaceAll(body, "\r", "")
	stripped := detailsBlock.ReplaceAllString(body, "")
	logs := stripped != body
	text := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(stripped), "🤖"))

	var usage []EmbedField
	if m := usageNote.FindStringSubmatch(text); m != nil {
		text = strings.Replace(text, m[0], "", 1)
		usage = []EmbedField{{Name: "Model", Value: fieldValue(m[1]), Inline: true}}
		if m[2] != "" {
			usage = append(usage, EmbedField{Name: "Reasoning", Value: fieldValue(m[2]), Inline: true})
		}
		usage = append(usage,
			EmbedField{Name: "Tokens", Value: fieldValue(compactTokens(m[3])), Inline: true},
			EmbedField{Name: "Est. cost (API)", Value: fieldValue(m[4]), Inline: true})
	}

	e := Embed{Title: "🤖 Agent update", Color: colorNeutral}
	first, rest, _ := strings.Cut(text, "\n")
	switch {
	case startedRe.MatchString(text):
		m := startedRe.FindStringSubmatch(text)
		e = Embed{Title: "🤖 Agent started", URL: m[4], Color: colorInfo, Description: "[Follow the run](" + m[4] + ")",
			Fields: []EmbedField{
				{Name: "Harness", Value: fieldValue("`" + m[1] + "`"), Inline: true},
				{Name: "Mode", Value: fieldValue("`" + m[2] + "`"), Inline: true},
				{Name: "Branch", Value: fieldValue("`" + m[3] + "`"), Inline: true},
			}}
		text = ""
	case openedRe.MatchString(first) && strings.TrimSpace(rest) == "":
		m := openedRe.FindStringSubmatch(first)
		e = Embed{Title: "📬 PR #" + m[2] + " opened", URL: m[1], Color: colorSuccess}
		text = ""
	case pushedRe.MatchString(first):
		m := pushedRe.FindStringSubmatch(first)
		e = Embed{Title: "⬆️ Pushed to PR #" + m[3], URL: m[2], Color: colorSuccess,
			Fields: []EmbedField{{Name: "Commit", Value: "`" + short(m[1]) + "`", Inline: true}}}
		text = strings.TrimSpace(rest)
	case strings.Contains(first, "did not produce a change"):
		e = Embed{Title: "❌ The agent run failed", Color: colorFailure}
	case strings.Contains(first, "made no changes"):
		e = Embed{Title: "🤷 The agent made no changes", Color: colorWarning}
	case strings.HasPrefix(first, "Not starting the agent"):
		e = Embed{Title: "⛔ The agent didn't start", Color: colorFailure}
	}
	e.Fields = append(e.Fields, usage...)

	text = formatPRLinks(strings.TrimSpace(text))
	link := ""
	if logs && url != "" {
		link = fmt.Sprintf("[Logs on GitHub](%s)", url)
	}
	if r := []rune(text); len(r) > maxDescription {
		text = string(r[:maxDescription]) + "…"
		link = ""
		if url != "" {
			link = fmt.Sprintf("[More on GitHub](%s)", url)
		}
	}
	if link != "" {
		text = strings.TrimSpace(text + "\n\n" + link)
	}
	if text != "" {
		e.Description = anglePreview.ReplaceAllString(text, "]($1)")
	}
	return e
}

func fieldValue(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return "—"
	}
	if r := []rune(s); len(r) > maxFieldValue {
		return string(r[:maxFieldValue]) + "…"
	}
	return s
}

// compactTokens shortens a token count: 1397530 is 1.4M, 42000 is 42K. Anything that
// isn't a whole number (such as "unavailable") is returned as is.
func compactTokens(s string) string {
	n, err := strconv.ParseUint(s, 10, 64)
	if err != nil {
		return s
	}
	if n < 1000 {
		return s
	}
	units := []struct {
		size   float64
		suffix string
	}{{1e3, "K"}, {1e6, "M"}, {1e9, "B"}, {1e12, "T"}}
	for i, u := range units {
		v := math.Round(float64(n)/u.size*10) / 10
		if v < 1000 || i == len(units)-1 {
			return strings.TrimSuffix(strconv.FormatFloat(v, 'f', 1, 64), ".0") + u.suffix
		}
	}
	return s
}
