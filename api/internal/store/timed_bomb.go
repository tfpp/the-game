package store

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
)

// BombSnapshot deliberately contains no code. The single database row owns the
// puzzle across game-server restarts; there is no reset/delete API.
type BombSnapshot struct {
	Deadline  int64  `json:"deadline"`
	State     string `json:"state"`
	Remaining int64  `json:"remaining"`
	Message   string `json:"message"`
}

func ValidBombCode(code string) bool {
	if len(code) != 4 {
		return false
	}
	for _, c := range code {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// TimedBomb serializes expiry and guesses in the same transaction. Expiry wins
// at the deadline, including when nobody was online or the server was down.
func (s *Store) TimedBomb(ctx context.Context, now int64, guess string) (BombSnapshot, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return BombSnapshot{}, err
	}
	defer tx.Rollback()
	var count int
	if err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM timed_bomb").Scan(&count); err != nil {
		return BombSnapshot{}, err
	}
	if count == 0 {
		n, err := rand.Int(rand.Reader, big.NewInt(10000))
		if err != nil {
			return BombSnapshot{}, err
		}
		if _, err = tx.ExecContext(ctx, "INSERT INTO timed_bomb (id, code, deadline, state) VALUES (1, ?, ?, 'armed')", fmt.Sprintf("%04d", n.Int64()), now+86400); err != nil {
			return BombSnapshot{}, err
		}
	}
	var result BombSnapshot
	var code string
	var next int64
	if err = tx.QueryRowContext(ctx, "SELECT code, deadline, state, next_attempt FROM timed_bomb WHERE id = 1").Scan(&code, &result.Deadline, &result.State, &next); err != nil {
		return BombSnapshot{}, err
	}
	if result.State == "armed" && now >= result.Deadline {
		result.State = "exploded"
	}
	result.Message = "Enter the secret four-digit code."
	if guess != "" && result.State == "armed" {
		if now < next {
			result.Message = "Keypad cooling down. Try again shortly."
		} else {
			next = now + 5
			result.Message = "Incorrect code."
			if guess == code {
				result.State = "defused"
				result.Message = "Bomb defused."
			}
		}
	}
	if result.State == "exploded" {
		result.Message = "Bomb has gone off."
	}
	if result.State == "defused" {
		result.Message = "Bomb defused."
	}
	result.Remaining = max(int64(0), result.Deadline-now)
	if _, err = tx.ExecContext(ctx, "UPDATE timed_bomb SET state = ?, next_attempt = ? WHERE id = 1", result.State, next); err != nil {
		return BombSnapshot{}, err
	}
	return result, tx.Commit()
}
