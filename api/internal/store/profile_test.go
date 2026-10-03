package store

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestProfileTracksHeartbeatTimeAcrossRestartAndLinking(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "profiles.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { s.Close() }()
	a, err := s.CreateEmailAccount(ctx, "profile@example.com", "hash", "Player", time.Unix(1000, 0))
	if err != nil {
		t.Fatal(err)
	}
	// No retroactive time, and no name-based matching.
	if _, err := s.ProfileByDiscord(ctx, "Player"); !errors.Is(err, ErrNotFound) {
		t.Fatal(err)
	}
	if err := s.LinkDiscord(ctx, a.ID, "123", "discord-name", time.Unix(1000, 0)); err != nil {
		t.Fatal(err)
	}
	check := func(want int64) {
		t.Helper()
		p, err := s.ProfileByDiscord(ctx, "123")
		if err != nil || p.PlaytimeSeconds != want || p.DisplayName != "Player" {
			t.Fatalf("profile: %+v %v; want %d", p, err, want)
		}
	}
	check(0)
	for i := int64(0); i <= 12; i++ {
		rate := int64(500)
		if i > 6 {
			rate = 425
		}
		if _, err := s.AccrueIncome(ctx, a.ID, 1000+i*5, rate); err != nil {
			t.Fatal(err)
		}
	}
	check(60)
	// Replays, backwards clocks and concurrent sessions cannot count the same interval twice.
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := s.AccrueIncome(ctx, a.ID, 1065, 500); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if _, err := s.AccrueIncome(ctx, a.ID, 1005, 500); err != nil {
		t.Fatal(err)
	}
	check(65)
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	check(65)
	// Reconnect after a long absence doesn't accrue the absence.
	if _, err := s.AccrueIncome(ctx, a.ID, 2000, 500); err != nil {
		t.Fatal(err)
	}
	check(65)
	if _, err := s.AccrueIncome(ctx, a.ID, 2015, 425); err != nil {
		t.Fatal(err)
	}
	check(80)
	if _, err := s.AccrueIncome(ctx, a.ID, 2031, 500); err != nil {
		t.Fatal(err)
	}
	check(80)
	// Discord-only accounts work without a chosen name; rename updates the lookup.
	b, err := s.CreateDiscordAccount(ctx, "456", "other", time.Unix(2000, 0))
	if err != nil {
		t.Fatal(err)
	}
	p, err := s.ProfileByDiscord(ctx, "456")
	if err != nil || p.DisplayName != "" || p.PlaytimeSeconds != 0 {
		t.Fatalf("%+v %v", p, err)
	}
	if err := s.SetDisplayName(ctx, b.ID, "Renamed", time.Unix(2000, 0)); err != nil {
		t.Fatal(err)
	}
	p, err = s.ProfileByDiscord(ctx, "456")
	if err != nil || p.DisplayName != "Renamed" {
		t.Fatalf("%+v %v", p, err)
	}
}

func TestProfileMigrationPreservesExistingWallet(t *testing.T) {
	path := filepath.Join(t.TempDir(), "old.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	for _, migration := range migrations[:len(migrations)-1] {
		if _, err := db.Exec(migration); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec("PRAGMA user_version = 10"); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec("INSERT INTO accounts (discord_id, display_name, created_at, updated_at, money, income_seconds, income_seen, income_units) VALUES ('123', 'Old', 1000, 1000, 9000, 30, 1000, 15000)"); err != nil {
		t.Fatal(err)
	}
	db.Close()
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	p, err := s.ProfileByDiscord(context.Background(), "123")
	if err != nil || p.PlaytimeSeconds != 0 {
		t.Fatalf("%+v %v", p, err)
	}
	money, err := s.AccrueIncome(context.Background(), 1, 1005, 500)
	if err != nil || money != 9000 {
		t.Fatalf("%d %v", money, err)
	}
	p, _ = s.ProfileByDiscord(context.Background(), "123")
	if p.PlaytimeSeconds != 5 {
		t.Fatal(p)
	}
}
