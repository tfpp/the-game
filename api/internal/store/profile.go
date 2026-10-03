package store

import (
	"context"
	"database/sql"
	"errors"
)

// Profile deliberately excludes account IDs, contact details and wallet data.
type Profile struct {
	DisplayName     string `json:"display_name"`
	PlaytimeSeconds int64  `json:"playtime_seconds"`
}

// ProfileByDiscord uses the existing verified OAuth link, not a player-supplied name.
func (s *Store) ProfileByDiscord(ctx context.Context, discordID string) (Profile, error) {
	var p Profile
	err := s.db.QueryRowContext(ctx,
		"SELECT COALESCE(display_name, ''), playtime_seconds FROM accounts WHERE discord_id = ?",
		discordID).Scan(&p.DisplayName, &p.PlaytimeSeconds)
	if errors.Is(err, sql.ErrNoRows) {
		return Profile{}, ErrNotFound
	}
	return p, err
}
