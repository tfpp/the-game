package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
)

var ErrInsufficientMoney = errors.New("insufficient money")
var ErrSpinConflict = errors.New("spin belongs to another account")
var ErrCreditConflict = errors.New("credit belongs to another account")
var ErrChargeConflict = errors.New("charge belongs to another account")
var ErrLootSaleConflict = errors.New("loot sale does not match its original account and amount")
var ErrRouletteConflict = errors.New("roulette bet does not match its original account and amounts")

// CoinCreditCents is the flat reward for collecting a map coin pickup.
const CoinCreditCents = 1000

type Spin struct {
	Reels   [3]int `json:"reels"`
	Payout  int64  `json:"payout"`
	Balance int64  `json:"balance"`
}

// SlotPayout returns cents. Five equiprobable symbols give 125 combinations;
// the five winning prizes total 100x wagerCents, for an exact 80% return
// regardless of a machine's buy-in.
func SlotPayout(reels [3]int, wagerCents int64) int64 {
	if reels[0] < 0 || reels[0] >= 5 || reels[0] != reels[1] || reels[1] != reels[2] {
		return 0
	}
	return [5]int64{3000, 2000, 1000, 1500, 2500}[reels[0]] * wagerCents / 100
}

func (s *Store) Money(ctx context.Context, accountID int64) (int64, error) {
	var balance int64
	err := s.db.QueryRowContext(ctx, "SELECT money FROM accounts WHERE id = ?", accountID).Scan(&balance)
	return balance, err
}

// PlaySlot atomically charges wagerCents and pays, and records the result for
// safe retries. wagerCents lets each slot machine set its own buy-in.
func (s *Store) PlaySlot(ctx context.Context, accountID int64, id string, reels [3]int, wagerCents int64) (Spin, error) {
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
	result.Payout = SlotPayout(reels, wagerCents)
	err = tx.QueryRowContext(ctx, "UPDATE accounts SET money = money - ? + ? WHERE id = ? AND money >= ? RETURNING money", wagerCents, result.Payout, accountID, wagerCents).Scan(&result.Balance)
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

// CreditCoin atomically pays the flat map-coin reward and records the result for
// safe retries, the same idempotency pattern PlaySlot uses for paid spins.
func (s *Store) CreditCoin(ctx context.Context, accountID int64, id string) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var owner, balance int64
	err = tx.QueryRowContext(ctx, "SELECT account_id, balance FROM coin_credits WHERE id = ?", id).Scan(&owner, &balance)
	if err == nil {
		if owner != accountID {
			return 0, ErrCreditConflict
		}
		return balance, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	err = tx.QueryRowContext(ctx, "UPDATE accounts SET money = money + ? WHERE id = ? RETURNING money", CoinCreditCents, accountID).Scan(&balance)
	if err != nil {
		return 0, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO coin_credits VALUES (?, ?, ?)", id, accountID, balance); err != nil {
		return 0, err
	}
	return balance, tx.Commit()
}

// CreditLoot records a server-authorized sale and pays its value exactly once.
// A retry must name the same account and amount so an operation ID cannot be
// repurposed after a lost response.
func (s *Store) CreditLoot(ctx context.Context, accountID int64, id string, amountCents int64) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var owner, amount, balance int64
	err = tx.QueryRowContext(ctx, "SELECT account_id, amount, balance FROM loot_sales WHERE id = ?", id).Scan(&owner, &amount, &balance)
	if err == nil {
		if owner != accountID || amount != amountCents {
			return 0, ErrLootSaleConflict
		}
		return balance, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	err = tx.QueryRowContext(ctx, "UPDATE accounts SET money = money + ? WHERE id = ? RETURNING money", amountCents, accountID).Scan(&balance)
	if err != nil {
		return 0, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO loot_sales VALUES (?, ?, ?, ?)", id, accountID, amountCents, balance); err != nil {
		return 0, err
	}
	return balance, tx.Commit()
}

// ChargeAccount atomically deducts amountCents (rejecting if that would go
// negative) and records the result for safe retries, the same idempotency
// pattern CreditCoin uses in the other direction. Used by paid features like
// features/gun_machine that spend the persisted wallet on a one-off purchase.
func (s *Store) ChargeAccount(ctx context.Context, accountID int64, id string, amountCents int64) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var owner, balance int64
	err = tx.QueryRowContext(ctx, "SELECT account_id, balance FROM charges WHERE id = ?", id).Scan(&owner, &balance)
	if err == nil {
		if owner != accountID {
			return 0, ErrChargeConflict
		}
		return balance, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	err = tx.QueryRowContext(ctx, "UPDATE accounts SET money = money - ? WHERE id = ? AND money >= ? RETURNING money", amountCents, accountID, amountCents).Scan(&balance)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrInsufficientMoney
	}
	if err != nil {
		return 0, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO charges VALUES (?, ?, ?, ?)", id, accountID, amountCents, balance); err != nil {
		return 0, err
	}
	return balance, tx.Commit()
}

// SettleRoulette atomically deducts a player's total roulette wager and pays
// their winnings (stake included) for one spin, rejecting the whole bet if the
// balance cannot cover the wager. The game server resolves the wheel; a retry
// must repeat the same account and amounts so an operation ID cannot be reused.
func (s *Store) SettleRoulette(ctx context.Context, accountID int64, id string, wagerCents, payoutCents int64) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var owner, wager, payout, balance int64
	err = tx.QueryRowContext(ctx, "SELECT account_id, wager, payout, balance FROM roulette_bets WHERE id = ?", id).Scan(&owner, &wager, &payout, &balance)
	if err == nil {
		if owner != accountID || wager != wagerCents || payout != payoutCents {
			return 0, ErrRouletteConflict
		}
		return balance, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	err = tx.QueryRowContext(ctx, "UPDATE accounts SET money = money - ? + ? WHERE id = ? AND money >= ? RETURNING money", wagerCents, payoutCents, accountID, wagerCents).Scan(&balance)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrInsufficientMoney
	}
	if err != nil {
		return 0, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO roulette_bets VALUES (?, ?, ?, ?, ?)", id, accountID, wagerCents, payoutCents, balance); err != nil {
		return 0, err
	}
	return balance, tx.Commit()
}

// AccrueIncome is a server heartbeat for connected players. Short gaps accrue
// play time; gaps over 15 seconds pause it, so offline time never earns money.
// Keeping the timestamp and remainder in SQLite prevents reconnect/restart grants.
func (s *Store) AccrueIncome(ctx context.Context, accountID, now, incomeCents int64) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	var balance, seconds, seen, units, playtime int64
	if err = tx.QueryRowContext(ctx, "SELECT money, income_seconds, income_seen, income_units, playtime_seconds FROM accounts WHERE id = ?", accountID).Scan(&balance, &seconds, &seen, &units, &playtime); err != nil {
		return 0, err
	}
	elapsed := now - seen
	if seen > 0 && elapsed > 0 && elapsed <= 15 {
		seconds += elapsed
		playtime += elapsed
		units += elapsed * incomeCents
	}
	if seconds >= 60 {
		balance += units / 60
		seconds %= 60
		units %= 60
	}
	if now < seen {
		now = seen
	}
	if _, err = tx.ExecContext(ctx, "UPDATE accounts SET money = ?, income_seconds = ?, income_seen = ?, income_units = ?, playtime_seconds = ? WHERE id = ?", balance, seconds, now, units, playtime, accountID); err != nil {
		return 0, err
	}
	return balance, tx.Commit()
}
