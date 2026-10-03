package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
)

var ErrCosmeticConflict = errors.New("cosmetic transaction conflict")

type Cosmetics struct {
	Revision int64           `json:"revision"`
	Document json.RawMessage `json:"document"`
	Balance  int64           `json:"balance"`
}

func readCosmetics(ctx context.Context, tx *sql.Tx, account int64) (Cosmetics, error) {
	result := Cosmetics{Document: json.RawMessage(`{"crates":{},"skins":{},"equipped":{}}`)}
	var document string
	err := tx.QueryRowContext(ctx, "SELECT revision, document FROM cosmetics WHERE account_id = ?", account).Scan(&result.Revision, &document)
	if err == nil {
		result.Document = json.RawMessage(document)
	}
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return result, err
	}
	err = tx.QueryRowContext(ctx, "SELECT money FROM accounts WHERE id = ?", account).Scan(&result.Balance)
	return result, err
}

func (s *Store) Cosmetics(ctx context.Context, account int64) (Cosmetics, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Cosmetics{}, err
	}
	defer tx.Rollback()
	return readCosmetics(ctx, tx, account)
}

// CommitCosmetics uses the same accounts.money wallet as every other purchase.
// A revision CAS and an immutable operation ID atomically commit both the
// collection and money. Lost responses, reconnects and concurrent game servers
// cannot charge twice or overwrite a newer collection. Replays return current
// state (not a historical balance/document).
func (s *Store) CommitCosmetics(ctx context.Context, account int64, id string, revision, delta int64, document string) (Cosmetics, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Cosmetics{}, err
	}
	defer tx.Rollback()
	var owner, previousRevision, previousDelta int64
	var previousDocument string
	err = tx.QueryRowContext(ctx, "SELECT account_id, revision, delta, document FROM cosmetic_transactions WHERE id = ?", id).Scan(&owner, &previousRevision, &previousDelta, &previousDocument)
	if err == nil {
		if owner != account || previousRevision != revision || previousDelta != delta || previousDocument != document {
			return Cosmetics{}, ErrCosmeticConflict
		}
		return readCosmetics(ctx, tx, account)
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return Cosmetics{}, err
	}
	current, err := readCosmetics(ctx, tx, account)
	if err != nil {
		return Cosmetics{}, err
	}
	if current.Revision != revision {
		return Cosmetics{}, ErrCosmeticConflict
	}
	// Also bounds integer overflow on credits.
	if delta < 0 && current.Balance < -delta {
		return Cosmetics{}, ErrInsufficientMoney
	}
	if delta > 0 && current.Balance > (1<<63-1)-delta {
		return Cosmetics{}, ErrCosmeticConflict
	}
	balance := current.Balance + delta
	if _, err = tx.ExecContext(ctx, "UPDATE accounts SET money = ? WHERE id = ?", balance, account); err != nil {
		return Cosmetics{}, err
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO cosmetics VALUES (?, ?, ?) ON CONFLICT(account_id) DO UPDATE SET revision = excluded.revision, document = excluded.document`, account, revision+1, document); err != nil {
		return Cosmetics{}, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO cosmetic_transactions VALUES (?, ?, ?, ?, ?)", id, account, revision, delta, document); err != nil {
		return Cosmetics{}, err
	}
	result := Cosmetics{Revision: revision + 1, Document: json.RawMessage(document), Balance: balance}
	return result, tx.Commit()
}
