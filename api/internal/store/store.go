// Package store persists accounts, sessions and short-lived auth tokens in SQLite.
//
// Secrets (session tokens, email tokens, OAuth state, login codes) are stored only as
// SHA-256 hashes, so a leaked database cannot be replayed against the API.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite" // pure-Go SQLite driver, registered as "sqlite"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrExpired       = errors.New("expired")
	ErrNameTaken     = errors.New("display name taken")
	ErrEmailTaken    = errors.New("email taken")
	ErrDiscordLinked = errors.New("discord identity already linked")
)

// Account is one player. Email accounts always have a verified email and a password
// hash; Discord-only accounts have neither. DisplayName is empty until chosen.
type Account struct {
	ID              int64
	Email           string
	PasswordHash    string
	DiscordID       string
	DiscordUsername string
	DisplayName     string
	CreatedAt       time.Time
}

type Store struct {
	db *sql.DB
}

// Open opens (creating if needed) the database at path and applies migrations.
// Use ":memory:" for tests.
func Open(path string) (*Store, error) {
	dsn := "file:" + path + "?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_txlock=immediate"
	if path != ":memory:" {
		dsn += "&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)"
	}
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	// One connection serializes writes (no SQLITE_BUSY) and keeps ":memory:" a single DB.
	db.SetMaxOpenConns(1)
	s := &Store{db: db}
	if err := s.migrate(context.Background()); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

// Ping checks that the database answers.
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

// migrations are applied in order; PRAGMA user_version records how many ran.
// Never edit an applied migration: append a new one.
var migrations = []string{
	`CREATE TABLE accounts (
		id               INTEGER PRIMARY KEY,
		email            TEXT UNIQUE,
		password_hash    TEXT,
		discord_id       TEXT UNIQUE,
		discord_username TEXT,
		display_name     TEXT COLLATE NOCASE UNIQUE,
		created_at       INTEGER NOT NULL,
		updated_at       INTEGER NOT NULL
	);
	CREATE TABLE sessions (
		token_hash BLOB PRIMARY KEY,
		account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
		created_at INTEGER NOT NULL,
		expires_at INTEGER NOT NULL
	);
	CREATE INDEX sessions_account ON sessions(account_id);
	CREATE TABLE pending_signups (
		token_hash    BLOB PRIMARY KEY,
		email         TEXT NOT NULL,
		password_hash TEXT NOT NULL,
		display_name  TEXT NOT NULL,
		expires_at    INTEGER NOT NULL
	);
	CREATE TABLE reset_tokens (
		token_hash BLOB PRIMARY KEY,
		account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
		expires_at INTEGER NOT NULL
	);
	CREATE TABLE oauth_states (
		state_hash      BLOB PRIMARY KEY,
		code_challenge  TEXT NOT NULL,
		link_account_id INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
		expires_at      INTEGER NOT NULL
	);
	CREATE TABLE login_codes (
		code_hash      BLOB PRIMARY KEY,
		account_id     INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
		code_challenge TEXT NOT NULL,
		expires_at     INTEGER NOT NULL
	);`,
	`ALTER TABLE accounts ADD COLUMN money INTEGER NOT NULL DEFAULT 2000 CHECK(money >= 0);
	ALTER TABLE accounts ADD COLUMN income_seconds INTEGER NOT NULL DEFAULT 0;
	ALTER TABLE accounts ADD COLUMN income_seen INTEGER NOT NULL DEFAULT 0;
	CREATE TABLE slot_spins (
		id TEXT PRIMARY KEY,
		account_id INTEGER NOT NULL REFERENCES accounts(id),
		reels TEXT NOT NULL,
		payout INTEGER NOT NULL,
		balance INTEGER NOT NULL
	);`,
	`CREATE TABLE coin_credits (
		id TEXT PRIMARY KEY,
		account_id INTEGER NOT NULL REFERENCES accounts(id),
		balance INTEGER NOT NULL
	);`,
	`CREATE TABLE charges (
		id TEXT PRIMARY KEY,
		account_id INTEGER NOT NULL REFERENCES accounts(id),
		amount INTEGER NOT NULL,
		balance INTEGER NOT NULL
	);`,
	`ALTER TABLE accounts ADD COLUMN income_units INTEGER NOT NULL DEFAULT 0;
	UPDATE accounts SET income_units = income_seconds * 500;`,
	`CREATE TABLE loot_sales (
		id TEXT PRIMARY KEY,
		account_id INTEGER NOT NULL REFERENCES accounts(id),
		amount INTEGER NOT NULL,
		balance INTEGER NOT NULL
	);`,
}

func (s *Store) migrate(ctx context.Context) error {
	var version int
	if err := s.db.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	for i := version; i < len(migrations); i++ {
		tx, err := s.db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, migrations[i]); err != nil {
			tx.Rollback()
			return fmt.Errorf("migration %d: %w", i+1, err)
		}
		if _, err := tx.ExecContext(ctx, fmt.Sprintf("PRAGMA user_version = %d", i+1)); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

const accountCols = `id, COALESCE(email, ''), COALESCE(password_hash, ''), COALESCE(discord_id, ''),
	COALESCE(discord_username, ''), COALESCE(display_name, ''), created_at`

func scanAccount(row interface{ Scan(...any) error }) (Account, error) {
	var a Account
	var created int64
	err := row.Scan(&a.ID, &a.Email, &a.PasswordHash, &a.DiscordID, &a.DiscordUsername, &a.DisplayName, &created)
	if errors.Is(err, sql.ErrNoRows) {
		return Account{}, ErrNotFound
	}
	a.CreatedAt = time.Unix(created, 0)
	return a, err
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func isUnique(err error, column string) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE constraint failed: accounts."+column)
}

func (s *Store) AccountByID(ctx context.Context, id int64) (Account, error) {
	return scanAccount(s.db.QueryRowContext(ctx, "SELECT "+accountCols+" FROM accounts WHERE id = ?", id))
}

func (s *Store) AccountByEmail(ctx context.Context, email string) (Account, error) {
	return scanAccount(s.db.QueryRowContext(ctx, "SELECT "+accountCols+" FROM accounts WHERE email = ?", email))
}

func (s *Store) AccountByDiscordID(ctx context.Context, discordID string) (Account, error) {
	return scanAccount(s.db.QueryRowContext(ctx, "SELECT "+accountCols+" FROM accounts WHERE discord_id = ?", discordID))
}

// DisplayNameTaken reports whether name is in use, ignoring case.
func (s *Store) DisplayNameTaken(ctx context.Context, name string) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM accounts WHERE display_name = ?", name).Scan(&n)
	return n > 0, err
}

// CreateEmailAccount creates a verified email account. If displayName was taken in the
// meantime the account is created without one and the player picks another.
func (s *Store) CreateEmailAccount(ctx context.Context, email, passwordHash, displayName string, now time.Time) (Account, error) {
	insert := func(name string) (int64, error) {
		res, err := s.db.ExecContext(ctx,
			`INSERT INTO accounts (email, password_hash, display_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`,
			email, passwordHash, nullable(name), now.Unix(), now.Unix())
		if err != nil {
			return 0, err
		}
		return res.LastInsertId()
	}
	id, err := insert(displayName)
	if isUnique(err, "display_name") {
		id, err = insert("")
	}
	if isUnique(err, "email") {
		return Account{}, ErrEmailTaken
	}
	if err != nil {
		return Account{}, err
	}
	return s.AccountByID(ctx, id)
}

// CreateDiscordAccount creates an account for a Discord identity with no display name.
func (s *Store) CreateDiscordAccount(ctx context.Context, discordID, username string, now time.Time) (Account, error) {
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO accounts (discord_id, discord_username, created_at, updated_at) VALUES (?, ?, ?, ?)`,
		discordID, username, now.Unix(), now.Unix())
	if isUnique(err, "discord_id") {
		return Account{}, ErrDiscordLinked
	}
	if err != nil {
		return Account{}, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Account{}, err
	}
	return s.AccountByID(ctx, id)
}

// LinkDiscord attaches a Discord identity to an existing account.
func (s *Store) LinkDiscord(ctx context.Context, accountID int64, discordID, username string, now time.Time) error {
	res, err := s.db.ExecContext(ctx,
		`UPDATE accounts SET discord_id = ?, discord_username = ?, updated_at = ? WHERE id = ?`,
		discordID, username, now.Unix(), accountID)
	if isUnique(err, "discord_id") {
		return ErrDiscordLinked
	}
	return affected(res, err)
}

// UpdateDiscordUsername refreshes the cached Discord username after a sign-in.
func (s *Store) UpdateDiscordUsername(ctx context.Context, accountID int64, username string, now time.Time) error {
	res, err := s.db.ExecContext(ctx,
		`UPDATE accounts SET discord_username = ?, updated_at = ? WHERE id = ?`, username, now.Unix(), accountID)
	return affected(res, err)
}

func (s *Store) SetDisplayName(ctx context.Context, accountID int64, name string, now time.Time) error {
	res, err := s.db.ExecContext(ctx,
		`UPDATE accounts SET display_name = ?, updated_at = ? WHERE id = ?`, name, now.Unix(), accountID)
	if isUnique(err, "display_name") {
		return ErrNameTaken
	}
	return affected(res, err)
}

func (s *Store) SetPassword(ctx context.Context, accountID int64, passwordHash string, now time.Time) error {
	res, err := s.db.ExecContext(ctx,
		`UPDATE accounts SET password_hash = ?, updated_at = ? WHERE id = ?`, passwordHash, now.Unix(), accountID)
	return affected(res, err)
}

func affected(res sql.Result, err error) error {
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// Sessions.

func (s *Store) CreateSession(ctx context.Context, tokenHash []byte, accountID int64, now, expires time.Time) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO sessions (token_hash, account_id, created_at, expires_at) VALUES (?, ?, ?, ?)`,
		tokenHash, accountID, now.Unix(), expires.Unix())
	return err
}

// SessionAccount returns the account for a live session.
func (s *Store) SessionAccount(ctx context.Context, tokenHash []byte, now time.Time) (Account, error) {
	return scanAccount(s.db.QueryRowContext(ctx,
		"SELECT "+accountCols+` FROM accounts WHERE id =
		 (SELECT account_id FROM sessions WHERE token_hash = ? AND expires_at > ?)`, tokenHash, now.Unix()))
}

func (s *Store) DeleteSession(ctx context.Context, tokenHash []byte) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash = ?`, tokenHash)
	return err
}

// DeleteAccountSessions signs the account out everywhere (after a password reset).
func (s *Store) DeleteAccountSessions(ctx context.Context, accountID int64) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM sessions WHERE account_id = ?`, accountID)
	return err
}

// Single-use tokens. Take* deletes the row and fails with ErrExpired if it was stale.

type PendingSignup struct {
	Email        string
	PasswordHash string
	DisplayName  string
}

func (s *Store) CreatePendingSignup(ctx context.Context, tokenHash []byte, p PendingSignup, expires time.Time) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO pending_signups (token_hash, email, password_hash, display_name, expires_at) VALUES (?, ?, ?, ?, ?)`,
		tokenHash, p.Email, p.PasswordHash, p.DisplayName, expires.Unix())
	return err
}

func (s *Store) TakePendingSignup(ctx context.Context, tokenHash []byte, now time.Time) (PendingSignup, error) {
	var p PendingSignup
	var exp int64
	err := s.db.QueryRowContext(ctx,
		`DELETE FROM pending_signups WHERE token_hash = ? RETURNING email, password_hash, display_name, expires_at`,
		tokenHash).Scan(&p.Email, &p.PasswordHash, &p.DisplayName, &exp)
	return p, takeErr(err, exp, now)
}

func (s *Store) CreateResetToken(ctx context.Context, tokenHash []byte, accountID int64, expires time.Time) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO reset_tokens (token_hash, account_id, expires_at) VALUES (?, ?, ?)`,
		tokenHash, accountID, expires.Unix())
	return err
}

func (s *Store) TakeResetToken(ctx context.Context, tokenHash []byte, now time.Time) (int64, error) {
	var id, exp int64
	err := s.db.QueryRowContext(ctx,
		`DELETE FROM reset_tokens WHERE token_hash = ? RETURNING account_id, expires_at`, tokenHash).Scan(&id, &exp)
	return id, takeErr(err, exp, now)
}

// OAuthState is a pending Discord authorization. LinkAccountID is non-zero when a
// signed-in player is linking Discord to their existing account.
type OAuthState struct {
	CodeChallenge string
	LinkAccountID int64
}

func (s *Store) CreateOAuthState(ctx context.Context, stateHash []byte, st OAuthState, expires time.Time) error {
	var link any
	if st.LinkAccountID != 0 {
		link = st.LinkAccountID
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO oauth_states (state_hash, code_challenge, link_account_id, expires_at) VALUES (?, ?, ?, ?)`,
		stateHash, st.CodeChallenge, link, expires.Unix())
	return err
}

func (s *Store) TakeOAuthState(ctx context.Context, stateHash []byte, now time.Time) (OAuthState, error) {
	var st OAuthState
	var link sql.NullInt64
	var exp int64
	err := s.db.QueryRowContext(ctx,
		`DELETE FROM oauth_states WHERE state_hash = ? RETURNING code_challenge, link_account_id, expires_at`,
		stateHash).Scan(&st.CodeChallenge, &link, &exp)
	st.LinkAccountID = link.Int64
	return st, takeErr(err, exp, now)
}

func (s *Store) CreateLoginCode(ctx context.Context, codeHash []byte, accountID int64, codeChallenge string, expires time.Time) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO login_codes (code_hash, account_id, code_challenge, expires_at) VALUES (?, ?, ?, ?)`,
		codeHash, accountID, codeChallenge, expires.Unix())
	return err
}

func (s *Store) TakeLoginCode(ctx context.Context, codeHash []byte, now time.Time) (accountID int64, codeChallenge string, err error) {
	var exp int64
	err = s.db.QueryRowContext(ctx,
		`DELETE FROM login_codes WHERE code_hash = ? RETURNING account_id, code_challenge, expires_at`,
		codeHash).Scan(&accountID, &codeChallenge, &exp)
	return accountID, codeChallenge, takeErr(err, exp, now)
}

func takeErr(err error, expires int64, now time.Time) error {
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if expires <= now.Unix() {
		return ErrExpired
	}
	return nil
}

// PurgeExpired deletes stale sessions and tokens.
func (s *Store) PurgeExpired(ctx context.Context, now time.Time) error {
	for _, table := range []string{"sessions", "pending_signups", "reset_tokens", "oauth_states", "login_codes"} {
		if _, err := s.db.ExecContext(ctx, "DELETE FROM "+table+" WHERE expires_at <= ?", now.Unix()); err != nil {
			return err
		}
	}
	return nil
}
