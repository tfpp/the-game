package store

import (
	"context"
	"math"
	"testing"
	"time"
)

func fiveDollarDraw(bound int64) int64 {
	if bound == 9 {
		return 4
	}
	return 1
}

func TestIncomePrizeDecadesAndModelScale(t *testing.T) {
	for _, tc := range []struct{ digit, promotions, units, want int64 }{
		{0, 0, 30000, 100}, {8, 0, 30000, 900},
		{4, 0, 25500, 425}, {4, 0, 27750, 462},
		{0, 9, 30000, 100_000_000_000},
		{0, 10, 30000, 1_000_000_000_000},
	} {
		left := tc.promotions
		got := incomePrize(tc.units, func(bound int64) int64 {
			if bound == 9 {
				return tc.digit
			}
			if left > 0 {
				left--
				return 0
			}
			return 1
		})
		if got != tc.want {
			t.Fatalf("%+v: %d", tc, got)
		}
	}
	// Even a pathological always-promoting source terminates without overflow.
	if got := incomePrize(30000, func(int64) int64 { return 0 }); got != 1_000_000_000_000_000_000 {
		t.Fatal(got)
	}
}

func TestIncomeJackpotTransactionReplayAndOverflow(t *testing.T) {
	s, err := Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	a, err := s.CreateEmailAccount(ctx, "jackpot@example.com", "hash", "Jack", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	draws := 0
	draw := func(bound int64) int64 {
		draws++
		if bound == 9 {
			return 0
		}
		if draws <= 10 {
			return 0
		}
		return 1
	}
	for now := int64(1000); now <= 1060; now += 5 {
		if _, err := s.accrueIncome(ctx, a.ID, now, 500, draw); err != nil {
			t.Fatal(err)
		}
	}
	want := int64(100_000_002_000)
	for _, now := range []int64{1060, 1050, 2000} {
		got, err := s.accrueIncome(ctx, a.ID, now, 500, draw)
		if err != nil || got != want || draws != 11 {
			t.Fatalf("%d %v draws=%d", got, err, draws)
		}
	}
	// Saturate rather than letting SQLite silently convert overflowing money to REAL.
	if _, err := s.db.ExecContext(ctx, "UPDATE accounts SET money = ? WHERE id = ?", int64(math.MaxInt64-50), a.ID); err != nil {
		t.Fatal(err)
	}
	for now := int64(2005); now <= 2060; now += 5 {
		got, err := s.accrueIncome(ctx, a.ID, now, 500, fiveDollarDraw)
		if err != nil {
			t.Fatal(err)
		}
		if now == 2060 && got != math.MaxInt64 {
			t.Fatal(got)
		}
	}
}
