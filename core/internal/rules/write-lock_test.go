package rules

import (
	"context"
	"errors"
	"slices"
	"sync"
	"testing"
	"time"

	"spacevibe.dev/core/internal/mutate"
)

// The cell write plans inside the write lock from the document it edits, and every write looks at ctx again inside the
// lock. A writer that never takes our lock (Claude Code) is simulated with Store.beforeLockedRead.

// A rule for one command added between the preview and the write makes the cell mixed: the write is refused (409) and
// the file keeps exactly what the other writer left.
func TestSetCapabilityRefusesACellThatBecameMixed(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read"]}}`)
	other := `{"permissions":{"allow":["Read"],"deny":["Bash(rm *)"]}}`
	sb.store.beforeLockedRead = func() { sb.write(".claude/settings.json", other) }
	before := mustPreview(t, sb, Run)
	if before.Current != StateNone {
		t.Fatalf("setup: Run starts as %v", before.Current)
	}
	_, err := sb.store.SetCapability(Global, Run, Allow)
	if m := wantErr(t, err, 409); m != "Run commands has rules for specific paths or commands here, so it has no single value. Edit the individual rules instead." {
		t.Errorf("message %q", m)
	}
	if got := sb.read(".claude/settings.json"); got != other {
		t.Errorf("file changed: %q", got)
	}
	if len(historyOf(t, sb.r)) != 0 {
		t.Error("a refused write left a journal entry")
	}
}

// The rules the write replaces are the ones in the locked document, not the ones the preview saw.
func TestSetCapabilityReplacesWhatTheLockedDocumentHolds(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", `{"permissions":{"allow":["Read"]}}`)
	sb.store.beforeLockedRead = func() { sb.write(".claude/settings.json", `{"permissions":{"ask":["Read"]}}`) }
	if _, err := sb.store.SetCapability(Global, Read, Deny); err != nil {
		t.Fatal(err)
	}
	if ask, _ := permissionList(t, sb.settings(), Ask); len(ask) != 0 {
		t.Errorf("the rule the other writer put there stays: %v", ask)
	}
	if deny, _ := permissionList(t, sb.settings(), Deny); !slices.Equal(deny, []string{"Read"}) {
		t.Errorf("deny %v", deny)
	}
}

func mustPreview(t *testing.T, sb sandbox, c Capability) Preview {
	t.Helper()
	return must(sb.store.PreviewSetCapability(Global, c, Allow))
}

// A request cancelled before it holds the lock changes nothing, for every write.
func TestCancelledWriteChangesNothing(t *testing.T) {
	const original = `{"permissions":{"allow":["Read"]}}`
	sb := newSandbox(t)
	sb.write(".claude/settings.json", original)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	sb.store.ctx = ctx
	writes := map[string]func() error{
		"set":    func() error { _, err := sb.store.SetCapability(Global, Read, Deny); return err },
		"add":    func() error { _, err := sb.store.AddRule(Global, Allow, "Edit"); return err },
		"remove": func() error { _, err := sb.store.RemoveRule(Global, Allow, "Read"); return err },
		"change": func() error { _, err := sb.store.ChangeVerdict(Global, "Read", Allow, Deny); return err },
	}
	for name, write := range writes {
		if err := write(); !errors.Is(err, context.Canceled) {
			t.Errorf("%s: err %v, want context canceled", name, err)
		}
	}
	if got := sb.read(".claude/settings.json"); got != original {
		t.Errorf("file changed: %q", got)
	}
	if len(historyOf(t, sb.r)) != 0 {
		t.Error("a cancelled write left a journal entry")
	}
}

// Through the service: the request is cancelled while it waits for a lock another writer holds.
func TestServiceWriteCancelledWhileQueued(t *testing.T) {
	const original = `{"permissions":{"allow":["Read"]}}`
	sb := newSandbox(t)
	sb.write(".claude/settings.json", original)
	s := newService(t, sb)
	ctx, cancel := context.WithCancel(context.Background())

	held, release := make(chan struct{}), make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		_ = mutate.WithLock(sb.r, func(*mutate.Tx) error { close(held); <-release; return nil })
	}()
	<-held
	done := make(chan error, 1)
	go func() {
		_, err := s.SetCapability(ctx, CapabilityParams{Scope: KindGlobal, Capability: Read, Verdict: Deny})
		done <- err
	}()
	time.Sleep(100 * time.Millisecond)
	cancel()
	close(release)
	wg.Wait()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Errorf("err %v, want context canceled", err)
	}
	if got := sb.read(".claude/settings.json"); got != original {
		t.Errorf("file changed: %q", got)
	}
}
