package store

import (
	"context"
	"path/filepath"
	"sync"
	"testing"
)

func TestTimedBombPersistenceAndDeadline(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bomb.db")
	st, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	first, err := st.TimedBomb(ctx, 100, "")
	if err != nil || first.Deadline != 86500 || first.State != "armed" {
		t.Fatal(first, err)
	}
	var code string
	if err := st.db.QueryRow("SELECT code FROM timed_bomb").Scan(&code); err != nil {
		t.Fatal(err)
	}
	if !ValidBombCode(code) {
		t.Fatal("invalid generated code format")
	}
	st.Close()
	st, err = Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	second, err := st.TimedBomb(ctx, 200, "")
	if err != nil || second.Deadline != first.Deadline || second.Remaining != 86300 {
		t.Fatal(second, err)
	}
	// Deadline wins even with the right code, after a full day offline.
	expired, err := st.TimedBomb(ctx, first.Deadline, code)
	if err != nil || expired.State != "exploded" {
		t.Fatal(expired, err)
	}
	later, err := st.TimedBomb(ctx, 300, code)
	if err != nil || later.State != "exploded" {
		t.Fatal(later, err)
	}
}

func TestTimedBombSharedCooldownAndTerminalDefusal(t *testing.T) {
	st, err := Open(":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	ctx := context.Background()
	if _, err = st.TimedBomb(ctx, 100, ""); err != nil {
		t.Fatal(err)
	}
	// Synthetic puzzle code belongs only to this isolated test database.
	if _, err = st.db.Exec("UPDATE timed_bomb SET code = '0042'"); err != nil {
		t.Fatal(err)
	}
	wrong, err := st.TimedBomb(ctx, 101, "0000")
	if err != nil || wrong.State != "armed" || wrong.Message != "Incorrect code." {
		t.Fatal(wrong, err)
	}
	blocked, err := st.TimedBomb(ctx, 102, "0042")
	if err != nil || blocked.State != "armed" {
		t.Fatal(blocked, err)
	}
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			result, err := st.TimedBomb(ctx, 106, "0042")
			if err != nil || result.State != "defused" {
				t.Error(result, err)
			}
		}()
	}
	wg.Wait()
	result, err := st.TimedBomb(ctx, 100000, "9999")
	if err != nil || result.State != "defused" {
		t.Fatal(result, err)
	}
}

func TestBombCodeSchema(t *testing.T) {
	for _, code := range []string{"", "123", "12345", " 123", "-123", "１２３４", "abcd"} {
		if ValidBombCode(code) {
			t.Error("invalid code accepted")
		}
	}
	if !ValidBombCode("0000") || !ValidBombCode("9999") {
		t.Fatal("valid code rejected")
	}
}
