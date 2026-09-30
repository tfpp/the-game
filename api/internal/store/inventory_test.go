package store

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

func TestInventorySurvivesReopen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "inventory.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	a, err := s.CreateEmailAccount(ctx, "inv@example.com", "hash", "Ivy", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if items, err := s.Inventory(ctx, a.ID); err != nil || items != "" {
		t.Fatalf("empty: %q %v", items, err)
	}
	if err := s.SaveInventory(ctx, a.ID, `{"hand":"old"}`, 1); err != nil {
		t.Fatal(err)
	}
	if err := s.SaveInventory(ctx, a.ID, `{"hand":"burger"}`, 2); err != nil {
		t.Fatal(err)
	}
	s.Close()
	s, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if items, err := s.Inventory(ctx, a.ID); err != nil || items != `{"hand":"burger"}` {
		t.Fatalf("reopened: %q %v", items, err)
	}
	if err := s.SaveInventory(ctx, 9999, `{}`, 3); err == nil {
		t.Fatal("saved inventory for a missing account")
	}
}
