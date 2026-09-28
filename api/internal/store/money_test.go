package store

import (
	"context"
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestWalletPersistenceAndIdempotency(t *testing.T) {
	path := filepath.Join(t.TempDir(), "money.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	a, err := s.CreateEmailAccount(ctx, "a@example.com", "hash", "Alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	balance, err := s.Money(ctx, a.ID)
	if err != nil || balance != 2000 {
		t.Fatalf("starter: %d %v", balance, err)
	}
	got, err := s.PlaySlot(ctx, a.ID, "one", [3]int{0, 0, 0})
	if err != nil || got.Balance != 4900 || got.Payout != 3000 {
		t.Fatalf("win: %+v %v", got, err)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	replay, err := s.PlaySlot(ctx, a.ID, "one", [3]int{1, 2, 3})
	if err != nil || replay != got {
		t.Fatalf("retry: %+v %v", replay, err)
	}
	balance, _ = s.Money(ctx, a.ID)
	if balance != 4900 {
		t.Fatal(balance)
	}
	b, _ := s.CreateEmailAccount(ctx, "b@example.com", "hash", "Bob", time.Now())
	if _, err = s.PlaySlot(ctx, b.ID, "one", [3]int{}); !errors.Is(err, ErrSpinConflict) {
		t.Fatal(err)
	}
	if err = s.SetDisplayName(ctx, a.ID, "Renamed", time.Now()); err != nil {
		t.Fatal(err)
	}
	balance, _ = s.Money(ctx, a.ID)
	if balance != 4900 {
		t.Fatal(balance)
	}
}

func TestCoinCreditIsIdempotentAndPersists(t *testing.T) {
	path := filepath.Join(t.TempDir(), "coin.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	a, err := s.CreateEmailAccount(ctx, "coin@example.com", "hash", "Alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	balance, err := s.CreditCoin(ctx, a.ID, "one")
	if err != nil || balance != 3000 {
		t.Fatalf("credit: %d %v", balance, err)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	replay, err := s.CreditCoin(ctx, a.ID, "one")
	if err != nil || replay != 3000 {
		t.Fatalf("retry paid again: %d %v", replay, err)
	}
	balance, _ = s.Money(ctx, a.ID)
	if balance != 3000 {
		t.Fatal(balance)
	}
	b, _ := s.CreateEmailAccount(ctx, "coin-b@example.com", "hash", "Bob", time.Now())
	if _, err = s.CreditCoin(ctx, b.ID, "one"); !errors.Is(err, ErrCreditConflict) {
		t.Fatal(err)
	}
}

func TestChargeAccountIsIdempotentAndRejectsInsufficientFunds(t *testing.T) {
	path := filepath.Join(t.TempDir(), "charge.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	a, err := s.CreateEmailAccount(ctx, "charge@example.com", "hash", "Alice", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	balance, err := s.ChargeAccount(ctx, a.ID, "one", 1500)
	if err != nil || balance != 500 {
		t.Fatalf("charge: %d %v", balance, err)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	replay, err := s.ChargeAccount(ctx, a.ID, "one", 1500)
	if err != nil || replay != 500 {
		t.Fatalf("retry charged again: %d %v", replay, err)
	}
	balance, _ = s.Money(ctx, a.ID)
	if balance != 500 {
		t.Fatal(balance)
	}
	if _, err = s.ChargeAccount(ctx, a.ID, "two", 600); !errors.Is(err, ErrInsufficientMoney) {
		t.Fatal(err)
	}
	balance, _ = s.Money(ctx, a.ID)
	if balance != 500 {
		t.Fatalf("insufficient charge should not touch balance: %d", balance)
	}
	b, _ := s.CreateEmailAccount(ctx, "charge-b@example.com", "hash", "Bob", time.Now())
	if _, err = s.ChargeAccount(ctx, b.ID, "one", 100); !errors.Is(err, ErrChargeConflict) {
		t.Fatal(err)
	}
}

func TestConcurrentSpinsCannotOverdraw(t *testing.T) {
	s, err := Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	a, _ := s.CreateEmailAccount(ctx, "a@example.com", "hash", "Alice", time.Now())
	var wg sync.WaitGroup
	for i := 0; i < 40; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, err := s.PlaySlot(ctx, a.ID, string(rune('a'+i)), [3]int{0, 1, 2})
			if err != nil && !errors.Is(err, ErrInsufficientMoney) {
				t.Error(err)
			}
		}(i)
	}
	wg.Wait()
	balance, _ := s.Money(ctx, a.ID)
	if balance != 0 {
		t.Fatal(balance)
	}
	_, err = s.PlaySlot(ctx, a.ID, "unfunded jackpot", [3]int{0, 0, 0})
	if !errors.Is(err, ErrInsufficientMoney) {
		t.Fatal(err)
	}
}

func TestSlotExpectedReturn(t *testing.T) {
	var total int64
	for a := 0; a < 5; a++ {
		for b := 0; b < 5; b++ {
			for c := 0; c < 5; c++ {
				total += SlotPayout([3]int{a, b, c})
			}
		}
	}
	if total != 10000 {
		t.Fatalf("125 spins should return $100, got %d cents", total)
	}
}

func TestIncomePausesAndSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "income.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	a, _ := s.CreateEmailAccount(ctx, "a@example.com", "hash", "Alice", time.Now())
	for now := int64(1000); now <= 1060; now += 5 {
		balance, err := s.AccrueIncome(ctx, a.ID, now, 500)
		want := int64(2000)
		if now == 1060 {
			want = 2500
		}
		if err != nil || balance != want {
			t.Fatalf("at %d: %d %v", now, balance, err)
		}
	}
	balance, _ := s.AccrueIncome(ctx, a.ID, 1060, 500)
	if balance != 2500 {
		t.Fatal(balance)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	balance, _ = s.AccrueIncome(ctx, a.ID, 2000, 500)
	if balance != 2500 {
		t.Fatal("offline income", balance)
	}
	for now := int64(2005); now <= 2060; now += 5 {
		balance, err = s.AccrueIncome(ctx, a.ID, now, 500)
		if err != nil {
			t.Fatal(err)
		}
	}
	if balance != 3000 {
		t.Fatal(balance)
	}
}

func TestIncomeUsesRateAcrossModelChanges(t *testing.T) {
	s, err := Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	a, _ := s.CreateEmailAccount(ctx, "girl@example.com", "hash", "Girl", time.Now())
	s.AccrueIncome(ctx, a.ID, 1000, 500)
	for now := int64(1005); now <= 1030; now += 5 {
		s.AccrueIncome(ctx, a.ID, now, 500)
	}
	for now := int64(1035); now <= 1060; now += 5 {
		balance, err := s.AccrueIncome(ctx, a.ID, now, 425)
		if err != nil {
			t.Fatal(err)
		}
		if now == 1060 && balance != 2462 {
			t.Fatalf("mixed minute earned %d, want 2462", balance)
		}
	}
	for now := int64(1065); now <= 1120; now += 5 {
		balance, err := s.AccrueIncome(ctx, a.ID, now, 425)
		if err != nil {
			t.Fatal(err)
		}
		if now == 1120 && balance != 2887 {
			t.Fatalf("girl minute earned %d, want 2887", balance)
		}
	}
}
