// Package server is the HTTP API: accounts, sessions and game join tickets.
//
// Every route lives under /api/ so one hostname can route /api/* here and everything
// else to the game server. Clients authenticate with "Authorization: Bearer <session>";
// there are no cookies, because the web client runs on a different site (GitHub Pages).
package server

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/tfpp/the-game/api/internal/auth"
	"github.com/tfpp/the-game/api/internal/discord"
	"github.com/tfpp/the-game/api/internal/mail"
	"github.com/tfpp/the-game/api/internal/store"
	"github.com/tfpp/the-game/api/internal/ticket"
)

const (
	sessionTTL   = 30 * 24 * time.Hour
	signupTTL    = 24 * time.Hour
	resetTTL     = time.Hour
	oauthTTL     = 10 * time.Minute
	loginCodeTTL = 2 * time.Minute
	ticketTTL    = 60 * time.Second
	maxBodyBytes = 16 << 10
)

type Config struct {
	// PublicURL is where this API is reachable, without /api (https://game.chrisbox.dev).
	PublicURL string
	// ClientURL is the web client page. Email links and the Discord callback send the
	// player back here with a #fragment, which browsers never send to servers.
	ClientURL string
	// AllowedOrigins get CORS access (exact match, e.g. https://tfpp.github.io).
	AllowedOrigins []string
	// TrustCFConnectingIP uses Cloudflare's CF-Connecting-IP header as the client IP.
	// Enable only when every request arrives through Cloudflare (the tunnel).
	TrustCFConnectingIP bool
	TicketKey           []byte
	Logger              *slog.Logger
	Now                 func() time.Time
}

type Server struct {
	cfg     Config
	store   *store.Store
	mailer  mail.Mailer      // nil: email sign-up and reset are disabled
	discord discord.Provider // nil: Discord sign-in is disabled
	log     *slog.Logger
	origins map[string]bool

	limits map[string]*limiter
	mailWG sync.WaitGroup
}

func New(cfg Config, st *store.Store, mailer mail.Mailer, d discord.Provider) *Server {
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	s := &Server{
		cfg: cfg, store: st, mailer: mailer, discord: d, log: cfg.Logger,
		origins: map[string]bool{},
		limits: map[string]*limiter{
			"signup-ip":      newLimiter(5, 2*time.Minute),
			"email-addr":     newLimiter(3, 20*time.Minute), // signup/reset mails per address
			"login-ip":       newLimiter(20, 30*time.Second),
			"login-email":    newLimiter(10, time.Minute),
			"reset-ip":       newLimiter(5, 2*time.Minute),
			"token-ip":       newLimiter(20, 30*time.Second), // verify, reset confirm, discord
			"name-account":   newLimiter(10, 6*time.Minute),
			"ticket-account": newLimiter(20, 3*time.Second),
		},
	}
	for _, o := range cfg.AllowedOrigins {
		s.origins[strings.TrimRight(o, "/")] = true
	}
	return s
}

// WaitMail blocks until queued mail has been handed to the mailer (tests, shutdown).
func (s *Server) WaitMail() { s.mailWG.Wait() }

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/game/money", s.gameMoney)
	mux.HandleFunc("POST /api/game/inventory", s.gameInventory)
	mux.HandleFunc("POST /api/game/timed-bomb", s.gameTimedBomb)
	mux.HandleFunc("GET /api/health", s.health)
	mux.HandleFunc("POST /api/auth/signup", s.signup)
	mux.HandleFunc("POST /api/auth/verify-email", s.verifyEmail)
	mux.HandleFunc("POST /api/auth/login", s.login)
	mux.HandleFunc("POST /api/auth/logout", s.logout)
	mux.HandleFunc("POST /api/auth/password-reset/request", s.resetRequest)
	mux.HandleFunc("POST /api/auth/password-reset/confirm", s.resetConfirm)
	mux.HandleFunc("POST /api/auth/discord/start", s.discordStart)
	mux.HandleFunc("GET /api/auth/discord/callback", s.discordCallback)
	mux.HandleFunc("POST /api/auth/discord/exchange", s.discordExchange)
	mux.HandleFunc("GET /api/me", s.me)
	mux.HandleFunc("PUT /api/me/display-name", s.setDisplayName)
	mux.HandleFunc("POST /api/join-ticket", s.joinTicket)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "not_found", "no such endpoint")
	})
	return s.cors(mux)
}

// cors allows the configured origins to call the API with a bearer token. Credentials
// (cookies) are never allowed.
func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Add("Vary", "Origin")
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Cache-Control", "no-store")
		origin := r.Header.Get("Origin")
		allowed := origin != "" && s.origins[origin]
		if allowed {
			h.Set("Access-Control-Allow-Origin", origin)
		}
		if r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != "" {
			if allowed {
				h.Set("Access-Control-Allow-Methods", "GET, POST, PUT")
				h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
				h.Set("Access-Control-Max-Age", "600")
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Responses.

type apiError struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, apiError{Error: code, Message: message})
}

func (s *Server) internalError(w http.ResponseWriter, r *http.Request, err error) {
	s.log.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
	writeError(w, http.StatusInternalServerError, "internal", "something went wrong; try again")
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "request body must be JSON")
		return false
	}
	return true
}

type accountJSON struct {
	ID              int64  `json:"id"`
	DisplayName     string `json:"display_name"`
	Email           string `json:"email"`
	DiscordLinked   bool   `json:"discord_linked"`
	DiscordUsername string `json:"discord_username"`
}

func toJSON(a store.Account) accountJSON {
	return accountJSON{
		ID: a.ID, DisplayName: a.DisplayName, Email: a.Email,
		DiscordLinked: a.DiscordID != "", DiscordUsername: a.DiscordUsername,
	}
}

type sessionJSON struct {
	Token   string      `json:"token"`
	Account accountJSON `json:"account"`
}

// Helpers.

func (s *Server) clientIP(r *http.Request) string {
	if s.cfg.TrustCFConnectingIP {
		if ip := r.Header.Get("CF-Connecting-IP"); ip != "" {
			return ip
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// limit applies the named limiter to key and writes a 429 if it's exhausted.
func (s *Server) limit(w http.ResponseWriter, name, key string) bool {
	ok, wait := s.limits[name].allow(key, s.cfg.Now())
	if !ok {
		secs := int(wait.Seconds()) + 1
		w.Header().Set("Retry-After", strconv.Itoa(secs))
		writeError(w, http.StatusTooManyRequests, "rate_limited", "too many attempts; wait a bit and try again")
	}
	return ok
}

// sendMail hands a message to the mailer in the background, so response timing
// doesn't depend on whether an email was sent (and so doesn't reveal accounts).
func (s *Server) sendMail(m mail.Message) {
	s.mailWG.Add(1)
	go func() {
		defer s.mailWG.Done()
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := s.mailer.Send(ctx, m); err != nil {
			s.log.Error("send mail failed", "subject", m.Subject, "err", err)
		}
	}()
}

func (s *Server) clientLink(fragment string) string {
	return strings.SplitN(s.cfg.ClientURL, "#", 2)[0] + "#" + fragment
}

func (s *Server) newSession(ctx context.Context, accountID int64) (string, error) {
	token := auth.NewToken()
	now := s.cfg.Now()
	return token, s.store.CreateSession(ctx, auth.HashToken(token), accountID, now, now.Add(sessionTTL))
}

func (s *Server) writeSession(w http.ResponseWriter, r *http.Request, a store.Account) {
	token, err := s.newSession(r.Context(), a.ID)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, sessionJSON{Token: token, Account: toJSON(a)})
}

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
		return strings.TrimSpace(h[7:])
	}
	return ""
}

// authenticate returns the session's account, or writes a 401.
func (s *Server) authenticate(w http.ResponseWriter, r *http.Request) (store.Account, bool) {
	token := bearer(r)
	if token != "" {
		a, err := s.store.SessionAccount(r.Context(), auth.HashToken(token), s.cfg.Now())
		if err == nil {
			return a, true
		}
		if !errors.Is(err, store.ErrNotFound) {
			s.internalError(w, r, err)
			return store.Account{}, false
		}
	}
	writeError(w, http.StatusUnauthorized, "unauthorized", "sign in again")
	return store.Account{}, false
}

func (s *Server) requireMail(w http.ResponseWriter) bool {
	if s.mailer == nil {
		writeError(w, http.StatusServiceUnavailable, "email_disabled", "email sign-in isn't available right now")
		return false
	}
	return true
}

// Handlers.

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	if err := s.store.Ping(r.Context()); err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok": true, "email": s.mailer != nil, "discord": s.discord != nil,
	})
}

// signup starts an email sign-up. The account only exists once the emailed link is
// followed, and it gets the password from *this* request, so someone who signs up with
// another person's address can't pre-set their password. The response is the same
// whether or not the address already has an account.
func (s *Server) signup(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	}
	if !s.requireMail(w) || !decode(w, r, &req) {
		return
	}
	email, err := auth.NormalizeEmail(req.Email)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_email", err.Error())
		return
	}
	if err := auth.ValidatePassword(req.Password); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_password", err.Error())
		return
	}
	if err := auth.ValidateDisplayName(req.DisplayName); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_name", err.Error())
		return
	}
	if !s.limit(w, "signup-ip", s.clientIP(r)) {
		return
	}
	ctx := r.Context()
	// Names are public, so saying one is taken reveals nothing about emails.
	if taken, err := s.store.DisplayNameTaken(ctx, req.DisplayName); err != nil {
		s.internalError(w, r, err)
		return
	} else if taken {
		writeError(w, http.StatusConflict, "name_taken", "that name is taken")
		return
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	accepted := func() {
		writeJSON(w, http.StatusAccepted, map[string]string{"status": "check_email"})
	}
	// Past the per-address limit, answer as usual but stop mailing that inbox.
	if ok, _ := s.limits["email-addr"].allow(email, s.cfg.Now()); !ok {
		accepted()
		return
	}
	_, err = s.store.AccountByEmail(ctx, email)
	switch {
	case err == nil:
		s.sendMail(mail.Message{
			To:      email,
			Subject: "You already have a The Game account",
			Text: "Someone (hopefully you) tried to sign up for The Game with this address, " +
				"but it already has an account.\n\nForgot your password? Reset it here:\n" +
				s.clientLink("forgot") + "\n\nIf this wasn't you, you can ignore this email.\n",
		})
	case errors.Is(err, store.ErrNotFound):
		token := auth.NewToken()
		p := store.PendingSignup{Email: email, PasswordHash: hash, DisplayName: req.DisplayName}
		if err := s.store.CreatePendingSignup(ctx, auth.HashToken(token), p, s.cfg.Now().Add(signupTTL)); err != nil {
			s.internalError(w, r, err)
			return
		}
		s.sendMail(mail.Message{
			To:      email,
			Subject: "Confirm your The Game account",
			Text: "Welcome to The Game! Confirm your email to finish creating your account:\n" +
				s.clientLink("verify="+token) + "\n\nThe link expires in 24 hours. " +
				"If you didn't sign up, you can ignore this email.\n",
		})
	default:
		s.internalError(w, r, err)
		return
	}
	accepted()
}

func (s *Server) verifyEmail(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Token string `json:"token"`
	}
	if !decode(w, r, &req) || !s.limit(w, "token-ip", s.clientIP(r)) {
		return
	}
	ctx := r.Context()
	p, err := s.store.TakePendingSignup(ctx, auth.HashToken(req.Token), s.cfg.Now())
	if errors.Is(err, store.ErrNotFound) || errors.Is(err, store.ErrExpired) {
		writeError(w, http.StatusBadRequest, "invalid_token", "that link is invalid or expired; sign up again")
		return
	} else if err != nil {
		s.internalError(w, r, err)
		return
	}
	a, err := s.store.CreateEmailAccount(ctx, p.Email, p.PasswordHash, p.DisplayName, s.cfg.Now())
	if errors.Is(err, store.ErrEmailTaken) {
		writeError(w, http.StatusConflict, "email_taken", "this email already has an account; sign in instead")
		return
	} else if err != nil {
		s.internalError(w, r, err)
		return
	}
	s.log.Info("account created", "account", a.ID, "via", "email")
	s.writeSession(w, r, a)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !decode(w, r, &req) || !s.limit(w, "login-ip", s.clientIP(r)) {
		return
	}
	email, err := auth.NormalizeEmail(req.Email)
	if err != nil || len(req.Password) > 4*auth.MaxPasswordLen {
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "wrong email or password")
		return
	}
	if !s.limit(w, "login-email", email) {
		return
	}
	a, err := s.store.AccountByEmail(r.Context(), email)
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		s.internalError(w, r, err)
		return
	}
	if err != nil || a.PasswordHash == "" {
		auth.BurnPasswordCheck(req.Password)
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "wrong email or password")
		return
	}
	ok, err := auth.VerifyPassword(req.Password, a.PasswordHash)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	if !ok {
		writeError(w, http.StatusUnauthorized, "invalid_credentials", "wrong email or password")
		return
	}
	s.writeSession(w, r, a)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if token := bearer(r); token != "" {
		if err := s.store.DeleteSession(r.Context(), auth.HashToken(token)); err != nil {
			s.internalError(w, r, err)
			return
		}
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) resetRequest(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email string `json:"email"`
	}
	if !s.requireMail(w) || !decode(w, r, &req) || !s.limit(w, "reset-ip", s.clientIP(r)) {
		return
	}
	accepted := func() {
		writeJSON(w, http.StatusAccepted, map[string]string{"status": "check_email"})
	}
	email, err := auth.NormalizeEmail(req.Email)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_email", err.Error())
		return
	}
	if ok, _ := s.limits["email-addr"].allow(email, s.cfg.Now()); !ok {
		accepted()
		return
	}
	ctx := r.Context()
	a, err := s.store.AccountByEmail(ctx, email)
	if errors.Is(err, store.ErrNotFound) {
		accepted()
		return
	} else if err != nil {
		s.internalError(w, r, err)
		return
	}
	token := auth.NewToken()
	if err := s.store.CreateResetToken(ctx, auth.HashToken(token), a.ID, s.cfg.Now().Add(resetTTL)); err != nil {
		s.internalError(w, r, err)
		return
	}
	s.sendMail(mail.Message{
		To:      email,
		Subject: "Reset your The Game password",
		Text: "Choose a new password for The Game here:\n" + s.clientLink("reset="+token) +
			"\n\nThe link expires in 1 hour. If you didn't ask for this, you can ignore this email.\n",
	})
	accepted()
}

func (s *Server) resetConfirm(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Token    string `json:"token"`
		Password string `json:"password"`
	}
	if !decode(w, r, &req) || !s.limit(w, "token-ip", s.clientIP(r)) {
		return
	}
	if err := auth.ValidatePassword(req.Password); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_password", err.Error())
		return
	}
	ctx := r.Context()
	now := s.cfg.Now()
	id, err := s.store.TakeResetToken(ctx, auth.HashToken(req.Token), now)
	if errors.Is(err, store.ErrNotFound) || errors.Is(err, store.ErrExpired) {
		writeError(w, http.StatusBadRequest, "invalid_token", "that link is invalid or expired; request a new one")
		return
	} else if err != nil {
		s.internalError(w, r, err)
		return
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	if err := s.store.SetPassword(ctx, id, hash, now); err != nil {
		s.internalError(w, r, err)
		return
	}
	// Sign out everywhere else: a reset usually means the old password is compromised.
	if err := s.store.DeleteAccountSessions(ctx, id); err != nil {
		s.internalError(w, r, err)
		return
	}
	a, err := s.store.AccountByID(ctx, id)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	s.writeSession(w, r, a)
}

// discordStart begins Discord sign-in (or, with a session and link=true, linking).
// The client sends code_challenge = hex(sha256(verifier)) and keeps the verifier, so
// only the browser that started the flow can redeem the resulting login code.
func (s *Server) discordStart(w http.ResponseWriter, r *http.Request) {
	var req struct {
		CodeChallenge string `json:"code_challenge"`
		Link          bool   `json:"link"`
	}
	if !decode(w, r, &req) || !s.limit(w, "token-ip", s.clientIP(r)) {
		return
	}
	if s.discord == nil {
		writeError(w, http.StatusServiceUnavailable, "discord_disabled", "Discord sign-in isn't available right now")
		return
	}
	if !auth.ValidChallenge(req.CodeChallenge) {
		writeError(w, http.StatusBadRequest, "bad_request", "code_challenge must be 64 lowercase hex characters")
		return
	}
	st := store.OAuthState{CodeChallenge: req.CodeChallenge}
	if req.Link {
		a, ok := s.authenticate(w, r)
		if !ok {
			return
		}
		st.LinkAccountID = a.ID
	}
	state := auth.NewToken()
	if err := s.store.CreateOAuthState(r.Context(), auth.HashToken(state), st, s.cfg.Now().Add(oauthTTL)); err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"url": s.discord.AuthURL(state)})
}

// discordCallback is where Discord redirects the browser. It never returns a session:
// it sends the player back to the client with a one-time code in the URL fragment.
func (s *Server) discordCallback(w http.ResponseWriter, r *http.Request) {
	fail := func(code string) {
		http.Redirect(w, r, s.clientLink("auth_error="+code), http.StatusFound)
	}
	if !s.limit(w, "token-ip", s.clientIP(r)) {
		return
	}
	if s.discord == nil {
		fail("discord_disabled")
		return
	}
	q := r.URL.Query()
	ctx := r.Context()
	now := s.cfg.Now()
	st, err := s.store.TakeOAuthState(ctx, auth.HashToken(q.Get("state")), now)
	if err != nil {
		if !errors.Is(err, store.ErrNotFound) && !errors.Is(err, store.ErrExpired) {
			s.log.Error("discord state lookup failed", "err", err)
		}
		fail("discord_expired")
		return
	}
	if q.Get("error") != "" || q.Get("code") == "" {
		fail("discord_cancelled")
		return
	}
	du, err := s.discord.Exchange(ctx, q.Get("code"))
	if err != nil {
		s.log.Warn("discord exchange failed", "err", err)
		fail("discord_failed")
		return
	}

	var accountID int64
	existing, err := s.store.AccountByDiscordID(ctx, du.ID)
	switch {
	case err != nil && !errors.Is(err, store.ErrNotFound):
		s.log.Error("discord account lookup failed", "err", err)
		fail("discord_failed")
		return
	case st.LinkAccountID != 0:
		if err == nil && existing.ID != st.LinkAccountID {
			fail("discord_in_use")
			return
		}
		target, err := s.store.AccountByID(ctx, st.LinkAccountID)
		if err != nil {
			fail("discord_failed")
			return
		}
		if target.DiscordID != "" && target.DiscordID != du.ID {
			fail("discord_already_linked")
			return
		}
		if err := s.store.LinkDiscord(ctx, target.ID, du.ID, du.Username, now); err != nil {
			s.log.Error("discord link failed", "err", err)
			fail("discord_failed")
			return
		}
		s.log.Info("discord linked", "account", target.ID)
		accountID = target.ID
	case err == nil:
		accountID = existing.ID
		if existing.DiscordUsername != du.Username {
			s.store.UpdateDiscordUsername(ctx, existing.ID, du.Username, now)
		}
	default:
		a, err := s.store.CreateDiscordAccount(ctx, du.ID, du.Username, now)
		if err != nil {
			s.log.Error("discord account create failed", "err", err)
			fail("discord_failed")
			return
		}
		s.log.Info("account created", "account", a.ID, "via", "discord")
		accountID = a.ID
	}

	code := auth.NewToken()
	if err := s.store.CreateLoginCode(ctx, auth.HashToken(code), accountID, st.CodeChallenge, now.Add(loginCodeTTL)); err != nil {
		s.log.Error("login code create failed", "err", err)
		fail("discord_failed")
		return
	}
	http.Redirect(w, r, s.clientLink("discord_code="+url.QueryEscape(code)), http.StatusFound)
}

func (s *Server) discordExchange(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code         string `json:"code"`
		CodeVerifier string `json:"code_verifier"`
	}
	if !decode(w, r, &req) || !s.limit(w, "token-ip", s.clientIP(r)) {
		return
	}
	ctx := r.Context()
	id, challenge, err := s.store.TakeLoginCode(ctx, auth.HashToken(req.Code), s.cfg.Now())
	if err == nil && !auth.ChallengeMatches(req.CodeVerifier, challenge) {
		err = store.ErrNotFound
	}
	if errors.Is(err, store.ErrNotFound) || errors.Is(err, store.ErrExpired) {
		writeError(w, http.StatusBadRequest, "invalid_code", "Discord sign-in expired; try again")
		return
	} else if err != nil {
		s.internalError(w, r, err)
		return
	}
	a, err := s.store.AccountByID(ctx, id)
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	s.writeSession(w, r, a)
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	a, ok := s.authenticate(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, toJSON(a))
}

func (s *Server) setDisplayName(w http.ResponseWriter, r *http.Request) {
	a, ok := s.authenticate(w, r)
	if !ok {
		return
	}
	var req struct {
		DisplayName string `json:"display_name"`
	}
	if !decode(w, r, &req) {
		return
	}
	if err := auth.ValidateDisplayName(req.DisplayName); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_name", err.Error())
		return
	}
	if req.DisplayName == a.DisplayName {
		writeJSON(w, http.StatusOK, toJSON(a))
		return
	}
	if !s.limit(w, "name-account", strconv.FormatInt(a.ID, 10)) {
		return
	}
	err := s.store.SetDisplayName(r.Context(), a.ID, req.DisplayName, s.cfg.Now())
	if errors.Is(err, store.ErrNameTaken) {
		writeError(w, http.StatusConflict, "name_taken", "that name is taken")
		return
	} else if err != nil {
		s.internalError(w, r, err)
		return
	}
	a.DisplayName = req.DisplayName
	writeJSON(w, http.StatusOK, toJSON(a))
}

func (s *Server) joinTicket(w http.ResponseWriter, r *http.Request) {
	a, ok := s.authenticate(w, r)
	if !ok || !s.limit(w, "ticket-account", strconv.FormatInt(a.ID, 10)) {
		return
	}
	if a.DisplayName == "" {
		writeError(w, http.StatusConflict, "display_name_required", "pick a display name first")
		return
	}
	exp := s.cfg.Now().Add(ticketTTL)
	t, err := ticket.Sign(s.cfg.TicketKey, ticket.Claims{
		AccountID: a.ID, Name: a.DisplayName, Expires: exp.Unix(), Nonce: auth.NewToken(),
	})
	if err != nil {
		s.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ticket": t, "expires_at": exp.Unix()})
}
