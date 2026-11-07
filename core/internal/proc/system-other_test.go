//go:build !darwin

package proc

import (
	"errors"
	"os"
	"testing"
)

func TestSystemNotMeasurable(t *testing.T) {
	a := NewSystem()
	if got, err := a.CodexThreads(ctx); a.Measurable() || a.IsAlive(ctx, os.Getpid()) || len(got) != 0 || err != nil {
		t.Fatal("a non-darwin adapter must see nothing")
	}
	if s, ok := a.StartTime(ctx, os.Getpid()); ok || s != "" {
		t.Fatalf("StartTime = %q, %v", s, ok)
	}
	if _, err := a.Identify(ctx, os.Getpid()); !errors.Is(err, ErrNotMeasurable) {
		t.Fatalf("Identify = %v", err)
	}
	if err := a.Terminate(ctx, os.Getpid()); !errors.Is(err, ErrNotMeasurable) {
		t.Fatalf("Terminate = %v", err)
	}
}
