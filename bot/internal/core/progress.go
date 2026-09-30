package core

// Live agent progress. While an agent runs, harness/progress.sh posts batches of its
// reasoning and tool calls; each bot run keeps one message in its feature's thread,
// edited at most every MinEdit, and marked finished when the workflow run completes.
//
// A run authenticates with ProgressToken(secret, request_id): the workflow derives it
// from AGENT_PROGRESS_SECRET in a step the agent can't see, so a run can only post to
// its own thread, and only while the bot considers it active.

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/tfpp/the-game/bot/internal/store"
)

// LiveChat posts a message that is edited later. The Discord adapter implements it.
type LiveChat interface {
	PostLive(ctx context.Context, threadID string, embed Embed) (messageID string, err error)
	EditLive(ctx context.Context, threadID, messageID string, embed Embed) error
}

// ProgressEvent is one streamed step: kind is reasoning, tool, note or error.
type ProgressEvent struct {
	Kind string `json:"kind"`
	Text string `json:"text"`
}

// ProgressUpdate is one batch from harness/progress.sh. Seq restarts at 1 for every
// adapter call, that is for every attempt.
type ProgressUpdate struct {
	RequestID string          `json:"request_id"`
	Agent     string          `json:"agent"`
	Model     string          `json:"model"`
	Seq       int             `json:"seq"`
	Attempt   int             `json:"attempt"`
	Attempts  int             `json:"attempts"`
	Events    []ProgressEvent `json:"events"`
}

var (
	// ErrProgressDenied: the token doesn't belong to the request ID.
	ErrProgressDenied = errors.New("progress: invalid token")
	// ErrProgressClosed: the run is unknown, finished or has no thread; stop sending.
	ErrProgressClosed = errors.New("progress: run is not active")
)

// MaxProgressEvents is the most events one update may carry.
const MaxProgressEvents = 200

const (
	liveLines      = 60            // rendered lines kept per run
	liveLineChars  = 360           // longest rendered reasoning line
	liveToolChars  = 150           // longest rendered tool call
	liveForget     = 6 * time.Hour // drop state of runs that never reported finishing
	liveMinEdit    = 3 * time.Second
	liveKeyPrefix  = "progress:"
	progressDomain = "agent-progress:"
)

var progressRequest = regexp.MustCompile(`^bot-(\d+)$`)

// ProgressToken is the token a run with requestID presents: hex HMAC-SHA256 of
// "agent-progress:<requestID>" keyed with the shared secret (see agent.yml).
func ProgressToken(secret []byte, requestID string) string {
	m := hmac.New(sha256.New, secret)
	m.Write([]byte(progressDomain + requestID))
	return hex.EncodeToString(m.Sum(nil))
}

// Progress keeps each active run's live message.
type Progress struct {
	svc     *Service
	chat    LiveChat
	secret  []byte
	MinEdit time.Duration // between edits of one message

	mu   sync.Mutex
	runs map[int64]*liveRun
	wg   sync.WaitGroup // pending flushes, for tests
}

type liveRun struct {
	threadID, messageID, url string
	agent, model             string
	attempt, attempts, seq   int
	lines                    []string
	thoughts, tools          int
	updated                  time.Time
	done                     bool
	conclusion               string

	timer           *time.Timer
	inflight, dirty bool
	lastEdit        time.Time
}

// NewProgress enables live progress on s, posting through chat.
func NewProgress(s *Service, chat LiveChat, secret []byte) *Progress {
	p := &Progress{svc: s, chat: chat, secret: secret, MinEdit: liveMinEdit, runs: map[int64]*liveRun{}}
	s.progress = p
	return p
}

// Update applies one batch. It returns ErrProgressDenied or ErrProgressClosed when the
// sender should stop; Discord errors are only logged.
func (p *Progress) Update(ctx context.Context, token string, u ProgressUpdate) error {
	if !hmac.Equal([]byte(token), []byte(ProgressToken(p.secret, u.RequestID))) {
		return ErrProgressDenied
	}
	m := progressRequest.FindStringSubmatch(u.RequestID)
	if m == nil {
		return ErrProgressClosed
	}
	id, err := strconv.ParseInt(m[1], 10, 64)
	if err != nil {
		return ErrProgressClosed
	}
	run, err := p.svc.st.RunByID(ctx, id)
	if errors.Is(err, store.ErrNotFound) {
		return ErrProgressClosed
	} else if err != nil {
		return err
	}
	switch run.Status {
	case store.RunDispatched, store.RunQueued, store.RunInProgress:
	default:
		return ErrProgressClosed
	}
	job, err := p.svc.st.JobByID(ctx, run.JobID)
	if errors.Is(err, store.ErrNotFound) {
		return ErrProgressClosed
	} else if err != nil {
		return err
	}
	if job.ThreadID == "" {
		return ErrProgressClosed
	}
	if len(u.Events) > MaxProgressEvents {
		u.Events = u.Events[len(u.Events)-MaxProgressEvents:]
	}
	now := p.svc.cfg.Now()

	p.mu.Lock()
	defer p.mu.Unlock()
	p.forget(now)
	lr := p.runs[id]
	if lr == nil {
		lr = &liveRun{threadID: job.ThreadID}
		// After a restart, keep editing the run's message rather than posting another.
		if msg, err := p.svc.st.Get(ctx, liveKeyPrefix+strconv.FormatInt(id, 10)); err == nil {
			lr.messageID = msg
		}
		p.runs[id] = lr
	}
	if lr.done {
		return ErrProgressClosed
	}
	if run.RunURL != "" {
		lr.url = run.RunURL
	}
	if !lr.apply(u) {
		return nil // repeated or out of order
	}
	lr.updated = now
	p.schedule(id, lr, now)
	return nil
}

// finish marks a run's message finished once its workflow run has completed.
func (p *Progress) finish(runID int64, conclusion string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	lr := p.runs[runID]
	if lr == nil || lr.done {
		return
	}
	lr.done, lr.conclusion = true, conclusion
	p.schedule(runID, lr, p.svc.cfg.Now())
}

// Wait blocks until every scheduled flush has run (tests).
func (p *Progress) Wait() {
	for {
		p.wg.Wait()
		p.mu.Lock()
		busy := false
		for _, lr := range p.runs {
			busy = busy || lr.timer != nil || lr.inflight
		}
		p.mu.Unlock()
		if !busy {
			return
		}
		time.Sleep(time.Millisecond)
	}
}

// forget drops runs that stopped reporting long ago without a finish. Holds p.mu.
func (p *Progress) forget(now time.Time) {
	for id, lr := range p.runs {
		if !lr.inflight && lr.timer == nil && now.Sub(lr.updated) > liveForget {
			delete(p.runs, id)
		}
	}
}

// schedule flushes lr now, or once MinEdit has passed since its last edit. Holds p.mu.
func (p *Progress) schedule(id int64, lr *liveRun, now time.Time) {
	if lr.timer != nil || lr.inflight {
		lr.dirty = true
		return
	}
	delay := lr.lastEdit.Add(p.MinEdit).Sub(now)
	if lr.messageID == "" || delay < 0 {
		delay = 0
	}
	p.wg.Add(1)
	lr.timer = time.AfterFunc(delay, func() {
		defer p.wg.Done()
		p.flush(id)
	})
}

func (p *Progress) flush(id int64) {
	p.mu.Lock()
	lr := p.runs[id]
	if lr == nil {
		p.mu.Unlock()
		return
	}
	lr.timer = nil
	lr.inflight, lr.dirty = true, false
	embed := lr.embed()
	thread, msg, done := lr.threadID, lr.messageID, lr.done
	p.mu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var err error
	if msg == "" {
		msg, err = p.chat.PostLive(ctx, thread, embed)
		if err == nil {
			if serr := p.svc.st.Set(ctx, liveKeyPrefix+strconv.FormatInt(id, 10), msg); serr != nil {
				p.svc.log.Error("save progress message", "err", serr, "run", id)
			}
		}
	} else {
		err = p.chat.EditLive(ctx, thread, msg, embed)
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	lr.inflight = false
	lr.lastEdit = p.svc.cfg.Now()
	if err != nil {
		p.svc.log.Error("live progress", "err", err, "run", id)
		msg = "" // deleted or never posted: post a fresh message next time
	}
	lr.messageID = msg
	switch {
	case lr.dirty || (lr.done && !done):
		p.schedule(id, lr, lr.lastEdit)
	case lr.done && err == nil:
		delete(p.runs, id)
	}
}

// apply adds an update's events, reporting false for a repeated or stale batch.
func (lr *liveRun) apply(u ProgressUpdate) bool {
	attempt := max(u.Attempt, 1)
	switch {
	case attempt < lr.attempt, attempt == lr.attempt && u.Seq <= lr.seq:
		return false
	case attempt > lr.attempt && lr.attempt > 0:
		lr.add(fmt.Sprintf("🔁 **Attempt %d**: fixing what verification found", attempt))
	}
	lr.attempt, lr.seq = attempt, u.Seq
	lr.attempts = max(u.Attempts, attempt)
	lr.agent, lr.model = cleanAgent(u.Agent), cleanModel(u.Model)
	for _, e := range u.Events {
		text := strings.Join(strings.Fields(e.Text), " ")
		if text == "" {
			continue
		}
		switch e.Kind {
		case "reasoning":
			lr.thoughts++
			lr.add("💭 " + balance(neutralize(clip(text, liveLineChars))))
		case "tool":
			lr.tools++
			lr.add("🔧 `" + clip(strings.ReplaceAll(text, "`", "ˋ"), liveToolChars) + "`")
		case "note":
			lr.add("ℹ️ " + balance(neutralize(clip(text, liveLineChars))))
		case "error":
			lr.add("⚠️ " + balance(neutralize(clip(text, liveLineChars))))
		}
	}
	return true
}

func (lr *liveRun) add(line string) {
	lr.lines = append(lr.lines, line)
	if len(lr.lines) > liveLines {
		lr.lines = lr.lines[len(lr.lines)-liveLines:]
	}
}

// embed renders the newest lines that fit, oldest first.
func (lr *liveRun) embed() Embed {
	e := Embed{Title: "🧠 Agent at work", URL: lr.url, Color: colorInfo}
	if lr.done {
		e.Title, e.Color = "🧠 Agent run finished", colorNeutral
	}
	var kept []string
	size := 0
	for i := len(lr.lines) - 1; i >= 0; i-- {
		n := utf8.RuneCountInString(lr.lines[i]) + 1
		if size+n > maxDescription-2 {
			kept = append(kept, "…")
			break
		}
		size += n
		kept = append(kept, lr.lines[i])
	}
	for i, j := 0, len(kept)-1; i < j; i, j = i+1, j-1 {
		kept[i], kept[j] = kept[j], kept[i]
	}
	e.Description = strings.Join(kept, "\n")
	if e.Description == "" {
		e.Description = "Starting up…"
	}
	who := lr.agent
	if lr.model != "" {
		who += " · " + lr.model
	}
	e.Fields = append(e.Fields, EmbedField{Name: "Agent", Value: "`" + who + "`", Inline: true})
	if lr.attempts > 1 {
		e.Fields = append(e.Fields, EmbedField{Name: "Attempt", Value: fmt.Sprintf("%d/%d", lr.attempt, lr.attempts), Inline: true})
	}
	e.Fields = append(e.Fields, EmbedField{Name: "Activity", Inline: true,
		Value: fmt.Sprintf("%s · %s", plural(lr.thoughts, "thought"), plural(lr.tools, "tool call"))})
	if lr.done {
		if lr.conclusion != "" && lr.conclusion != "success" {
			e.Fields = append(e.Fields, EmbedField{Name: "Workflow", Value: "`" + cleanModel(lr.conclusion) + "`", Inline: true})
		}
	} else {
		e.Fields = append(e.Fields, EmbedField{Name: "Updated", Value: fmt.Sprintf("<t:%d:R>", lr.updated.Unix()), Inline: true})
	}
	return e
}

func plural(n int, word string) string {
	if n == 1 {
		return "1 " + word
	}
	return fmt.Sprintf("%d %ss", n, word)
}

func clip(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n]) + "…"
}

// neutralize stops model text from forming masked links.
func neutralize(s string) string { return strings.ReplaceAll(s, "](", "]\u200b(") }

// balance drops markdown markers left unpaired, for example by clipping, so they can't
// restyle the lines after them.
func balance(s string) string {
	if strings.Count(s, "**")%2 == 1 {
		s = strings.ReplaceAll(s, "**", "")
	}
	if strings.Count(s, "`")%2 == 1 {
		s = strings.ReplaceAll(s, "`", "")
	}
	return s
}

func cleanAgent(a string) string {
	switch a {
	case "pi", "claude", "codex":
		return a
	}
	return "agent"
}

var unsafeModel = regexp.MustCompile(`[^A-Za-z0-9._/:-]`)

func cleanModel(m string) string { return clip(unsafeModel.ReplaceAllString(m, ""), 80) }
