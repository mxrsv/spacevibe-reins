package proc

import (
	"context"
	"math"
	"testing"
)

// unsafePids are pids that must never reach kill: kill(0, sig) signals the caller's process group,
// kill(-1, sig) every process the user may signal, and the rest do not fit in pid_t.
func unsafePids() []int {
	big := int64(math.MaxInt32) + 1
	return []int{0, -1, -4242, int(big), math.MaxInt, math.MinInt}
}

func TestValidPid(t *testing.T) {
	for _, pid := range unsafePids() {
		if validPid(pid) {
			t.Errorf("validPid(%d) = true", pid)
		}
	}
	for _, pid := range []int{1, 4242, math.MaxInt32} {
		if !validPid(pid) {
			t.Errorf("validPid(%d) = false", pid)
		}
	}
}

// Swift: ProcessGuardTests.swift "terminate refuses a pid that is zero, negative or does not fit in pid_t, before any signal"
// Runs against whichever System adapter this OS has: either refuses without signalling.
func TestSystemTerminateRefuses(t *testing.T) {
	a := NewSystem()
	want := ErrNoSuchProcess
	if !a.Measurable() {
		want = ErrNotMeasurable
	}
	for _, pid := range unsafePids() {
		if err := a.Terminate(context.Background(), pid); err != want {
			t.Errorf("Terminate(%d) = %v, want %v", pid, err, want)
		}
	}
}

// Swift: ProcessGuardTests.swift "isAlive is false for a pid that is zero, negative or too large, and startTime is nil"
func TestSystemIsAliveRefuses(t *testing.T) {
	a := NewSystem()
	for _, pid := range unsafePids() {
		if a.IsAlive(context.Background(), pid) {
			t.Errorf("IsAlive(%d) = true", pid)
		}
		if s, ok := a.StartTime(context.Background(), pid); ok || s != "" {
			t.Errorf("StartTime(%d) = %q, %v", pid, s, ok)
		}
	}
}

// The third Swift test, "stopSession with a status file that carries pid 0 or -1 finds no live session
// and signals nothing", needs stopSession and moves to the activity port (G2.2); its adapter half,
// IsAlive false for pid 0 and -1, is TestSystemIsAliveRefuses.
