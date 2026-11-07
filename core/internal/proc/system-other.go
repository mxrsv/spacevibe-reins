//go:build !darwin

package proc

import "context"

// System is the adapter where ps and lsof output is not parsed (only darwin is). It reports that
// nothing is measurable and never fails: no process is alive, no start time or thread is known, and
// Terminate returns ErrNotMeasurable without signalling anything.
type System struct{}

// NewSystem returns the not-measurable adapter.
func NewSystem() System { return System{} }

// Measurable is false on this OS.
func (System) Measurable() bool { return false }

// IsAlive is always false.
func (System) IsAlive(context.Context, int) bool { return false }

// StartTime is always unknown.
func (System) StartTime(context.Context, int) (string, bool) { return "", false }

// CodexThreads is always empty.
func (System) CodexThreads(context.Context) []Thread { return nil }

// Terminate always returns ErrNotMeasurable.
func (System) Terminate(context.Context, int) error { return ErrNotMeasurable }
