package store

import (
	"context"
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

const skinDoc = `{"crates":{},"skins":{"brine":2},"equipped":{"pistol":"brine"}}`

func TestCosmeticsAtomicReplayAndRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "skins.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	a, err := s.CreateEmailAccount(ctx, "skins@example.com", "hash", "Shrimp", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	initial, err := s.Cosmetics(ctx, a.ID)
	if err != nil || initial.Revision != 0 || initial.Balance != 2000 {
		t.Fatalf("initial: %+v %v", initial, err)
	}
	result, err := s.CommitCosmetics(ctx, a.ID, "purchase", 0, -500, skinDoc)
	if err != nil || result.Balance != 1500 || result.Revision != 1 {
		t.Fatalf("commit: %+v %v", result, err)
	}
	replay, err := s.CommitCosmetics(ctx, a.ID, "purchase", 0, -500, skinDoc)
	if err != nil || replay.Balance != 1500 || replay.Revision != 1 {
		t.Fatalf("replay: %+v %v", replay, err)
	}
	for _, change := range []struct {
		account, revision, delta int64
		doc                      string
	}{
		{a.ID, 0, -501, skinDoc}, {a.ID, 1, -500, skinDoc}, {a.ID, 0, -500, "{}"}, {a.ID + 1, 0, -500, skinDoc},
	} {
		_, err := s.CommitCosmetics(ctx, change.account, "purchase", change.revision, change.delta, change.doc)
		if !errors.Is(err, ErrCosmeticConflict) {
			t.Fatalf("altered replay accepted: %v", err)
		}
	}
	if _, err := s.CommitCosmetics(ctx, a.ID, "stale", 0, -500, skinDoc); !errors.Is(err, ErrCosmeticConflict) {
		t.Fatal(err)
	}
	if _, err := s.CommitCosmetics(ctx, a.ID, "broke", 1, -2000, "{}"); !errors.Is(err, ErrInsufficientMoney) {
		t.Fatal(err)
	}
	after, err := s.Cosmetics(ctx, a.ID)
	if err != nil || after.Revision != 1 || after.Balance != 1500 || string(after.Document) != skinDoc {
		t.Fatalf("rollback: %+v %v", after, err)
	}
	exchanged := `{"crates":{},"skins":{"brine":1},"equipped":{"pistol":"brine"}}`
	if _, err := s.CommitCosmetics(ctx, a.ID, "exchange", 1, 50, exchanged); err != nil {
		t.Fatal(err)
	}
	// A delayed old successful reply must return current state, not undo the exchange.
	replay, err = s.CommitCosmetics(ctx, a.ID, "purchase", 0, -500, skinDoc)
	if err != nil || replay.Balance != 1550 || replay.Revision != 2 || string(replay.Document) != exchanged {
		t.Fatalf("current replay: %+v %v", replay, err)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	after, err = s.Cosmetics(ctx, a.ID)
	if err != nil || after.Revision != 2 || after.Balance != 1550 || string(after.Document) != exchanged {
		t.Fatalf("restart: %+v %v", after, err)
	}
	if balance, err := s.Money(ctx, a.ID); err != nil || balance != 1550 {
		t.Fatalf("shared wallet: %d %v", balance, err)
	}
	// Existing ordinary inventory save cannot erase cosmetic data.
	if err := s.SaveInventory(ctx, a.ID, `{"hand":"pistol"}`, 1); err != nil {
		t.Fatal(err)
	}
	after, err = s.Cosmetics(ctx, a.ID)
	if err != nil || string(after.Document) != exchanged {
		t.Fatalf("inventory isolation: %+v %v", after, err)
	}
}

func TestCosmeticsSaveFailureRollsBackWallet(t *testing.T) {
	s, err := Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	a, err := s.CreateEmailAccount(ctx, "fail@example.com", "hash", "Fail", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.db.ExecContext(ctx, `CREATE TRIGGER fail_cosmetics BEFORE INSERT ON cosmetics BEGIN SELECT RAISE(ABORT, 'unavailable'); END`)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CommitCosmetics(ctx, a.ID, "save-fail", 0, -500, skinDoc); err == nil {
		t.Fatal("save should fail")
	}
	result, err := s.Cosmetics(ctx, a.ID)
	if err != nil || result.Balance != 2000 || result.Revision != 0 {
		t.Fatalf("charged without reward: %+v %v", result, err)
	}
	_, err = s.db.ExecContext(ctx, "DROP TRIGGER fail_cosmetics")
	if err != nil {
		t.Fatal(err)
	}
	result, err = s.CommitCosmetics(ctx, a.ID, "save-fail", 0, -500, skinDoc)
	if err != nil || result.Balance != 1500 || result.Revision != 1 {
		t.Fatalf("retry after outage: %+v %v", result, err)
	}
}

func TestCosmeticsConcurrentRequests(t *testing.T) {
	s, err := Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	a, err := s.CreateEmailAccount(ctx, "race@example.com", "hash", "Race", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for _, id := range []string{"one", "two"} {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			_, err := s.CommitCosmetics(ctx, a.ID, id, 0, -500, skinDoc)
			results <- err
		}(id)
	}
	wg.Wait()
	close(results)
	successes, conflicts := 0, 0
	for err := range results {
		if err == nil {
			successes++
		} else if errors.Is(err, ErrCosmeticConflict) {
			conflicts++
		} else {
			t.Fatal(err)
		}
	}
	if successes != 1 || conflicts != 1 {
		t.Fatalf("successes=%d conflicts=%d", successes, conflicts)
	}
	result, err := s.Cosmetics(ctx, a.ID)
	if err != nil || result.Balance != 1500 || result.Revision != 1 {
		t.Fatalf("race: %+v %v", result, err)
	}
}
