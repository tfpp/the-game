package store

import (
	"context"
	"database/sql"
	"errors"
)

// Inventory returns the account's saved inventory document (JSON written by the
// game server), or "" when none has been saved yet.
func (s *Store) Inventory(ctx context.Context, accountID int64) (string, error) {
	var items string
	err := s.db.QueryRowContext(ctx, "SELECT items FROM inventories WHERE account_id = ?", accountID).Scan(&items)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return items, err
}

// SaveInventory replaces the account's saved inventory document. The game server
// validates item IDs when it loads the document again.
func (s *Store) SaveInventory(ctx context.Context, accountID int64, items string, now int64) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO inventories (account_id, items, updated_at) VALUES (?, ?, ?)
		ON CONFLICT(account_id) DO UPDATE SET items = excluded.items, updated_at = excluded.updated_at`,
		accountID, items, now)
	return err
}
