//go:build unix

package mutate

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/inventory"
)

// A write cancelled while another process holds the data folder's flock (not another goroutine of ours) returns
// within the cancel, changes nothing and writes no journal entry; the lock then works for a normal write.
func TestCancelledWhileAnotherProcessHoldsTheFlockChangesNothing(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	skill := h.write(".claude/skills/wire/SKILL.md", skillMd("wire", "d"))
	id := idOf(t, r, "wire", inventory.KindSkill, inventory.Claude)
	svc := NewService(r)

	if err := os.MkdirAll(r.Data, 0o700); err != nil {
		t.Fatal(err)
	}
	other, err := os.OpenFile(filepath.Join(r.Data, fsx.LockFileName), os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if err := syscall.Flock(int(other.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { other.Close() })

	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(100*time.Millisecond, cancel)
	started := time.Now()
	_, err = svc.RemoveItem(ctx, IDParams{ID: id})
	if elapsed := time.Since(started); elapsed > 500*time.Millisecond {
		t.Errorf("returned after %v, want within 500 ms of the cancel", elapsed)
	}
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
	if !exists(skill) || exists(h.path(".spacevibe/journal.json")) {
		t.Fatal("a write cancelled while queued still ran")
	}

	other.Close() // the other process lets go
	if _, err := svc.RemoveItem(context.Background(), IDParams{ID: id}); err != nil {
		t.Fatalf("a normal write after the release: %v", err)
	}
	if exists(skill) {
		t.Error("the normal write did not remove the skill")
	}
}
