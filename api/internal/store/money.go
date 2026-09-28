package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
)

var ErrInsufficientMoney = errors.New("insufficient money")
var ErrSpinConflict = errors.New("spin belongs to another account")

type Spin struct {
	Reels   [3]int `json:"reels"`
	Payout  int64  `json:"payout"`
	Balance int64  `json:"balance"`
}

// SlotPayout returns cents. Five equiprobable symbols give 125 combinations;
// the five winning prizes total $100, for an exact 80% return on $1 spins.
func SlotPayout(reels [3]int) int64 {
	if reels[0] < 0 || reels[0] >= 5 || reels[0] != reels[1] || reels[1] != reels[2] {
		return 0
	}
	return [5]int64{3000, 2000, 1000, 1500, 2500}[reels[0]]
}

func (s *Store) Money(ctx context.Context, accountID int64) (int64, error) {
	var balance int64
	err := s.db.QueryRowContext(ctx, "SELECT money FROM accounts WHERE id = ?", accountID).Scan(&balance)
	return balance, err
}

// PlaySlot atomically charges and pays, and records the result for safe retries.
func (s *Store) PlaySlot(ctx context.Context, accountID int64, id string, reels [3]int) (Spin, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Spin{}, err
	}
	defer tx.Rollback()
	var result Spin
	var owner int64
	var encoded string
	err = tx.QueryRowContext(ctx, "SELECT account_id, reels, payout, balance FROM slot_spins WHERE id = ?", id).Scan(&owner, &encoded, &result.Payout, &result.Balance)
	if err == nil {
		if owner != accountID {
			return Spin{}, ErrSpinConflict
		}
		err = json.Unmarshal([]byte(encoded), &result.Reels)
		return result, err
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return Spin{}, err
	}
	result.Reels = reels
	result.Payout = SlotPayout(reels)
	err = tx.QueryRowContext(ctx, "UPDATE accounts SET money = money - 100 + ? WHERE id = ? AND money >= 100 RETURNING money", result.Payout, accountID).Scan(&result.Balance)
	if errors.Is(err, sql.ErrNoRows) {
		return Spin{}, ErrInsufficientMoney
	}
	if err != nil {
		return Spin{}, err
	}
	raw, _ := json.Marshal(reels)
	_, err = tx.ExecContext(ctx, "INSERT INTO slot_spins VALUES (?, ?, ?, ?, ?)", id, accountID, string(raw), result.Payout, result.Balance)
	if err != nil {
		return Spin{}, err
	}
	return result, tx.Commit()
}

// AccrueIncome is a server heartbeat for connected players. Short gaps accrue
// play time; gaps over 15 seconds pause it, so offline time never earns money.
// Keeping the timestamp and remainder in SQLite prevents reconnect/restart grants.
func (s *Store) AccrueIncome(ctx context.Context, accountID, now int64) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var balance, seconds, seen int64
	if err = tx.QueryRowContext(ctx, "SELECT money, income_seconds, income_seen FROM accounts WHERE id = ?", accountID).Scan(&balance, &seconds, &seen); err != nil {
		return 0, err
	}
	elapsed := now - seen
	if seen > 0 && elapsed > 0 && elapsed <= 15 {
		seconds += elapsed
	}
	balance += (seconds / 60) * 500
	seconds %= 60
	if now < seen {
		now = seen
	}
	if _, err = tx.ExecContext(ctx, "UPDATE accounts SET money = ?, income_seconds = ?, income_seen = ? WHERE id = ?", balance, seconds, now, accountID); err != nil {
		return 0, err
	}
	return balance, tx.Commit()
}
