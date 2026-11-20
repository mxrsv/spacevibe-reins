//go:build !darwin

package proc

import "context"

// CodexThreads is always empty (nothing is measurable, which Measurable says).
func (System) CodexThreads(context.Context) ([]Thread, error) { return nil, nil }
