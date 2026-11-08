//go:build unix

package rules

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"spacevibe.dev/core/internal/fsx"
)

// A rules write cancelled while another process holds the data folder's flock returns within the cancel, changes
// nothing and writes no journal entry; a normal write works after the other process lets go.
func TestServiceWriteCancelledWhileAnotherProcessHoldsTheFlock(t *testing.T) {
	const original = `{"permissions":{"allow":["Read"]}}`
	sb := newSandbox(t)
	sb.write(".claude/settings.json", original)
	s := newService(t, sb)

	if err := os.MkdirAll(sb.r.Data, 0o700); err != nil {
		t.Fatal(err)
	}
	other, err := os.OpenFile(filepath.Join(sb.r.Data, fsx.LockFileName), os.O_RDWR|os.O_CREATE, 0o600)
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
	_, err = s.SetCapability(ctx, CapabilityParams{Scope: KindGlobal, Capability: Read, Verdict: Deny})
	if elapsed := time.Since(started); elapsed > 500*time.Millisecond {
		t.Errorf("returned after %v, want within 500 ms of the cancel", elapsed)
	}
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
	if got := sb.read(".claude/settings.json"); got != original {
		t.Errorf("file changed: %q", got)
	}
	if len(historyOf(t, sb.r)) != 0 {
		t.Error("a cancelled write left a journal entry")
	}

	other.Close()
	if _, err := s.SetCapability(context.Background(), CapabilityParams{Scope: KindGlobal, Capability: Read, Verdict: Deny}); err != nil {
		t.Fatalf("a normal write after the release: %v", err)
	}
	if got := sb.read(".claude/settings.json"); got == original {
		t.Error("the normal write changed nothing")
	}
}
