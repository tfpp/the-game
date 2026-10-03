// Command api serves accounts, sessions and game join tickets.
//
// Configuration comes from the environment (see docs/architecture.md). Secrets are read
// from files, never from variables. Email and Discord sign-in switch themselves off
// (with a warning) until their secrets exist, so the service can be deployed first.
//
//	api              run the server
//	api healthcheck  exit 0 if the local server's /api/health answers (for Docker)
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/tfpp/the-game/api/internal/discord"
	"github.com/tfpp/the-game/api/internal/mail"
	"github.com/tfpp/the-game/api/internal/server"
	"github.com/tfpp/the-game/api/internal/store"
	"github.com/tfpp/the-game/api/internal/ticket"
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

// secret reads a trimmed secret file. A missing or empty file returns "".
func secret(path string) (string, error) {
	if path == "" {
		return "", nil
	}
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	return strings.TrimSpace(string(b)), err
}

func run(log *slog.Logger) error {
	addr := env("API_ADDR", ":8080")
	key, err := ticket.LoadKey(env("API_TICKET_KEY_FILE", "/run/secrets/ticket/ticket-key"))
	if err != nil {
		return fmt.Errorf("ticket key: %w", err)
	}
	st, err := store.Open(env("API_DB", "/data/api.db"))
	if err != nil {
		return fmt.Errorf("database: %w", err)
	}
	defer st.Close()

	publicURL := strings.TrimRight(env("API_PUBLIC_URL", "https://game.chrisbox.dev"), "/")
	cfg := server.Config{
		PublicURL:           publicURL,
		ClientURL:           env("API_CLIENT_URL", "https://tfpp.github.io/the-game/"),
		AllowedOrigins:      strings.Split(env("API_ALLOWED_ORIGINS", "https://tfpp.github.io"), ","),
		TrustCFConnectingIP: env("API_TRUST_CF_CONNECTING_IP", "") == "true",
		TicketKey:           key,
		Logger:              log,
	}

	profileKey, err := secret(env("API_PROFILE_KEY_FILE", "/run/secrets/api/profile-key"))
	if err != nil {
		return fmt.Errorf("profile key: %w", err)
	}
	if profileKey != "" && len(profileKey) < 32 {
		return errors.New("profile key must be at least 32 bytes")
	}
	cfg.ProfileKey = []byte(profileKey)

	var mailer mail.Mailer
	resendKey, err := secret(env("RESEND_API_KEY_FILE", "/run/secrets/api/resend-api-key"))
	if err != nil {
		return fmt.Errorf("resend key: %w", err)
	}
	switch {
	case env("API_DEV_LOG_MAIL", "") == "true":
		log.Warn("API_DEV_LOG_MAIL: emails (with their links) are logged, not sent")
		mailer = &mail.Log{Logger: log}
	case resendKey != "":
		from := os.Getenv("MAIL_FROM")
		if from == "" {
			return errors.New("MAIL_FROM is required when the Resend key is set")
		}
		mailer = &mail.Resend{APIKey: resendKey, From: from}
	default:
		log.Warn("no Resend API key: email sign-up and password reset are disabled")
	}

	var provider discord.Provider
	clientID := os.Getenv("DISCORD_CLIENT_ID")
	clientSecret, err := secret(env("DISCORD_CLIENT_SECRET_FILE", "/run/secrets/api/discord-client-secret"))
	if err != nil {
		return fmt.Errorf("discord secret: %w", err)
	}
	if clientID != "" && clientSecret != "" {
		provider = &discord.OAuth{
			ClientID: clientID, ClientSecret: clientSecret,
			RedirectURI: publicURL + "/api/auth/discord/callback",
		}
	} else {
		log.Warn("no Discord client ID or secret: Discord sign-in is disabled")
	}

	srv := server.New(cfg, st, mailer, provider)
	httpSrv := &http.Server{
		Addr:              addr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go purgeLoop(ctx, st, log)

	errc := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", addr, "email", mailer != nil, "discord", provider != nil)
		errc <- httpSrv.ListenAndServe()
	}()
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	err = httpSrv.Shutdown(shutdownCtx)
	srv.WaitMail()
	return err
}

func purgeLoop(ctx context.Context, st *store.Store, log *slog.Logger) {
	t := time.NewTicker(time.Hour)
	defer t.Stop()
	for {
		if err := st.PurgeExpired(ctx, time.Now()); err != nil && ctx.Err() == nil {
			log.Error("purge expired rows failed", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

func healthcheck() int {
	port := env("API_ADDR", ":8080")
	port = port[strings.LastIndexByte(port, ':')+1:]
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + port + "/api/health")
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
