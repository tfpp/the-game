// Command bot is the Discord bot: /feature and /revise start agent runs through the
// GitHub App, and GitHub webhooks report their progress back to Discord threads. With a
// progress secret, running agents also stream their reasoning to /bot/progress.
// /usage shows the agent's Claude and Codex subscription usage limits.
//
// Configuration comes from the environment (see bot/README.md). Secrets are read from
// files, never from variables.
//
//	bot              run the bot
//	bot healthcheck  exit 0 if the local bot's /bot/health answers (for Docker)
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/disgoorg/snowflake/v2"

	"github.com/tfpp/the-game/bot/internal/claude"
	"github.com/tfpp/the-game/bot/internal/codex"
	"github.com/tfpp/the-game/bot/internal/core"
	"github.com/tfpp/the-game/bot/internal/discordbot"
	"github.com/tfpp/the-game/bot/internal/github"
	"github.com/tfpp/the-game/bot/internal/store"
	"github.com/tfpp/the-game/bot/internal/webhook"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		os.Exit(healthcheck())
	}
	if err := run(log); err != nil {
		log.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) (int, error) {
	v := os.Getenv(key)
	if v == "" {
		return fallback, nil
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return n, nil
}

func envID(key string, required bool) (snowflake.ID, error) {
	v := os.Getenv(key)
	if v == "" {
		if required {
			return 0, fmt.Errorf("%s is required", key)
		}
		return 0, nil
	}
	id, err := snowflake.Parse(v)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return id, nil
}

// idString is id as a string, or "" for an unset (zero) ID.
func idString(id snowflake.ID) string {
	if id == 0 {
		return ""
	}
	return id.String()
}

// secret reads a required, trimmed secret file.
func secret(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	s := strings.TrimSpace(string(b))
	if s == "" {
		return "", fmt.Errorf("%s is empty", path)
	}
	return s, nil
}

func run(log *slog.Logger) error {
	addr := env("BOT_ADDR", ":8081")
	repo := env("BOT_REPO", "tfpp/the-game")

	guildID, err := envID("BOT_GUILD_ID", true)
	if err != nil {
		return err
	}
	roleID, err := envID("BOT_REQUESTER_ROLE_ID", true)
	if err != nil {
		return err
	}
	approverID, err := envID("BOT_APPROVER_ROLE_ID", false)
	if err != nil {
		return err
	}
	channelID, err := envID("BOT_FEATURE_CHANNEL_ID", false)
	if err != nil {
		return err
	}
	releaseChannelID, err := envID("BOT_RELEASE_CHANNEL_ID", false)
	if err != nil {
		return err
	}
	perUser, err := envInt("BOT_RUNS_PER_USER", 5)
	if err != nil {
		return err
	}
	maxActive, err := envInt("BOT_MAX_ACTIVE_RUNS", 5)
	if err != nil {
		return err
	}
	clientID := os.Getenv("BOT_GITHUB_CLIENT_ID")
	if clientID == "" {
		return errors.New("BOT_GITHUB_CLIENT_ID is required")
	}

	discordToken, err := secret(env("BOT_DISCORD_TOKEN_FILE", "/run/secrets/bot/discord-token"))
	if err != nil {
		return fmt.Errorf("discord token: %w", err)
	}
	keyPEM, err := secret(env("BOT_GITHUB_PRIVATE_KEY_FILE", "/run/secrets/bot/github-app.pem"))
	if err != nil {
		return fmt.Errorf("github app key: %w", err)
	}
	key, err := github.ParseKey([]byte(keyPEM))
	if err != nil {
		return fmt.Errorf("github app key: %w", err)
	}
	webhookSecret, err := secret(env("BOT_GITHUB_WEBHOOK_SECRET_FILE", "/run/secrets/bot/github-webhook-secret"))
	if err != nil {
		return fmt.Errorf("github webhook secret: %w", err)
	}

	// Optional: without the token, /usage says it isn't set up.
	var claudeClient *claude.Client
	claudeTokenFile := env("BOT_CLAUDE_TOKEN_FILE", "/run/secrets/bot/claude-token")
	if tok, err := secret(claudeTokenFile); err == nil {
		claudeClient = &claude.Client{Token: tok, HTTP: &http.Client{Timeout: 30 * time.Second}}
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("claude token: %w", err)
	}

	st, err := store.Open(env("BOT_DB", "/data/bot.db"))
	if err != nil {
		return fmt.Errorf("database: %w", err)
	}
	defer st.Close()

	gh := &github.App{ClientID: clientID, Key: key, Repo: repo, HTTP: &http.Client{Timeout: 30 * time.Second}}
	if _, err := gh.Token(context.Background()); err != nil {
		return fmt.Errorf("github app: %w", err)
	}

	dc, err := discordbot.New(discordbot.Config{
		Token: discordToken, GuildID: guildID, RequesterRoleID: roleID, ApproverRoleID: approverID,
		FeatureChannelID: channelID, Logger: log,
	})
	if err != nil {
		return fmt.Errorf("discord: %w", err)
	}
	var deployer core.Deployer
	if dir := os.Getenv("BOT_DEPLOY_DIR"); dir != "" {
		deployer = fileDeployer(dir)
	}
	svc := core.New(core.Config{
		Repo:             repo,
		Ref:              env("BOT_REF", "main"),
		Workflow:         env("BOT_WORKFLOW", "agent.yml"),
		CIWorkflow:       env("BOT_CI_WORKFLOW", "game-ci.yml"),
		ServerWorkflow:   env("BOT_SERVER_WORKFLOW", "server-image.yml"),
		PagesWorkflow:    env("BOT_PAGES_WORKFLOW", "pages.yml"),
		APIWorkflow:      env("BOT_API_WORKFLOW", "api-image.yml"),
		PreviewWorkflow:  env("BOT_PREVIEW_WORKFLOW", "preview.yml"),
		PreviewURL:       env("BOT_PREVIEW_URL", "https://pr-{pr}.tfpp-game.pages.dev/"),
		ReleaseChannelID: idString(releaseChannelID),
		Agent:            env("BOT_AGENT", "claude"),
		Limits: store.Limits{
			PerUser: perUser, Window: 24 * time.Hour,
			MaxActive: maxActive, StaleAfter: 3 * time.Hour,
		},
		Deployer: deployer,
		Logger:   log,
	}, st, gh, dc)
	dc.Service = svc
	dc.Claude = claudeClient
	// Read the optional auth file on cache misses so replacing a mounted login
	// takes effect without restarting the bot. Never write/refresh this shared login.
	dc.Codex = &codex.Client{
		AuthFile: env("BOT_CODEX_AUTH_FILE", "/run/secrets/bot/codex-auth.json"),
		HTTP:     &http.Client{Timeout: 30 * time.Second},
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	hooks := &webhook.Handler{Secret: []byte(webhookSecret), Repo: repo, Service: svc, Store: st, Logger: log}
	hooks.Start(ctx)
	mux := http.NewServeMux()
	mux.Handle("/bot/github", hooks)
	// Optional: live agent progress in feature threads (harness/progress.sh).
	if progressSecret, err := secret(env("BOT_PROGRESS_SECRET_FILE", "/run/secrets/bot/progress-secret")); err == nil {
		progress := core.NewProgress(svc, dc, []byte(progressSecret))
		mux.Handle("/bot/progress", &webhook.ProgressHandler{Progress: progress, Logger: log})
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("progress secret: %w", err)
	}
	mux.HandleFunc("GET /bot/health", func(w http.ResponseWriter, r *http.Request) {
		ok := st.Ping(r.Context()) == nil
		w.Header().Set("Content-Type", "application/json")
		if !ok {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		json.NewEncoder(w).Encode(map[string]bool{"ok": ok, "discord": dc.Ready()})
	})
	httpSrv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	if err := dc.Open(ctx); err != nil {
		return fmt.Errorf("discord: %w", err)
	}
	defer dc.Close(context.Background())
	go loop(ctx, log, "reconcile", 2*time.Minute, svc.Reconcile)
	go svc.RunCoordinator(ctx, time.Minute)
	go loop(ctx, log, "purge", 24*time.Hour, func(ctx context.Context) error {
		return st.Purge(ctx, time.Now(), 30*24*time.Hour)
	})

	errc := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", addr, "repo", repo)
		errc <- httpSrv.ListenAndServe()
	}()
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return httpSrv.Shutdown(shutdownCtx)
}

func loop(ctx context.Context, log *slog.Logger, name string, every time.Duration, f func(context.Context) error) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		if err := f(ctx); err != nil && ctx.Err() == nil {
			log.Error(name+" failed", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// fileDeployer asks the host to deploy builds through files in a directory it shares
// with the bot: the bot writes the commit to deploy to "request" (game server) or
// "api-request" (accounts API), and the host's deploy script writes the game server
// commit it deployed to "deployed".
type fileDeployer string

var shaRE = regexp.MustCompile(`^[0-9a-f]{40}$`)

func (d fileDeployer) Deploy(_ context.Context, sha string) error {
	return d.request("request", sha)
}

func (d fileDeployer) DeployAPI(_ context.Context, sha string) error {
	return d.request("api-request", sha)
}

// request atomically replaces the request file name with sha.
func (d fileDeployer) request(name, sha string) error {
	if !shaRE.MatchString(sha) {
		return fmt.Errorf("not a commit SHA: %q", sha)
	}
	tmp := filepath.Join(string(d), "."+name+".tmp")
	if err := os.WriteFile(tmp, []byte(sha+"\n"), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Join(string(d), name))
}

func (d fileDeployer) Deployed(context.Context) (string, error) {
	b, err := os.ReadFile(filepath.Join(string(d), "deployed"))
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	} else if err != nil {
		return "", err
	}
	sha := strings.TrimSpace(string(b))
	if !shaRE.MatchString(sha) {
		return "", nil
	}
	return sha, nil
}

func healthcheck() int {
	port := env("BOT_ADDR", ":8081")
	port = port[strings.LastIndexByte(port, ':')+1:]
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + port + "/bot/health")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Fprintln(os.Stderr, resp.Status)
		return 1
	}
	return 0
}
