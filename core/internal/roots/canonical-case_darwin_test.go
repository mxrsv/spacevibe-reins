package roots

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

// within fails the test if f does not return in time. A blocked open(2) cannot be cancelled, so the
// goroutine is left behind on failure; the test binary exits anyway.
func within(t *testing.T, d time.Duration, f func()) {
	t.Helper()
	done := make(chan struct{})
	go func() { f(); close(done) }()
	select {
	case <-done:
	case <-time.After(d):
		t.Fatalf("did not return within %s (blocked on open?)", d)
	}
}

// A FIFO with no writer blocks open(2) unless O_NONBLOCK is set; the root path may be any file.
func TestCanonicalCaseFIFOFinalComponentDoesNotBlock(t *testing.T) {
	h := newTempHome(t)
	if err := os.MkdirAll(h.url("MixedCase"), 0o755); err != nil {
		t.Fatal(err)
	}
	fifo := h.url("MixedCase/pipe")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Skipf("mkfifo unavailable: %v", err)
	}
	var got, resolved string
	within(t, 2*time.Second, func() {
		got = canonicalCase(fifo)
		resolved = ResolvedPath(fifo)
	})
	if got != fifo {
		t.Errorf("canonicalCase(fifo) = %q, want %q", got, fifo)
	}
	if resolved != fifo {
		t.Errorf("ResolvedPath(fifo) = %q, want %q", resolved, fifo)
	}
	// Stored spelling of the folders above the FIFO is still found (case-insensitive volumes only).
	if _, err := os.Stat(h.url("mixedcase")); err == nil {
		lower := filepath.Join(h.url("mixedcase"), "pipe")
		within(t, 2*time.Second, func() { got = canonicalCase(lower) })
		if got != fifo {
			t.Errorf("canonicalCase(%q) = %q, want %q", lower, got, fifo)
		}
	}
}
