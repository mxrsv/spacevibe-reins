package activity

import (
	"bytes"
	"context"
	"encoding/json"
	"time"

	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// WatchInterval is how often a subscription polls (docs/internals/core-protocol.md, "Activity subscription").
const WatchInterval = 3 * time.Second

// Service is the Activity methods over one engine: activity.read, the activity.subscribe poll and activity.stop.
// Reads and polls share the engine, so folded offsets are never repeated.
type Service struct {
	roots  roots.Roots
	proc   proc.Adapter
	opts   Options
	now    func() time.Time
	engine *Engine
}

// NewService builds a service. now is the clock every age is computed against (time.Now in the app, fixed in tests);
// a nil now means time.Now.
func NewService(r roots.Roots, adapter proc.Adapter, opts Options, now func() time.Time) *Service {
	if now == nil {
		now = time.Now
	}
	return &Service{roots: r, proc: adapter, opts: opts, now: now, engine: NewEngine()}
}

// Read is the full report (activity.read, and the resync after a restart: a full read, never a delta).
func (s *Service) Read(ctx context.Context) (Report, error) {
	return s.engine.Read(ctx, s.roots, s.now(), s.proc, s.opts)
}

// Watch reads once and passes that full snapshot to emit, then reads every interval and passes the full report to
// emit only when its encoding differs from the last one passed. "Changed" includes the clock: ageMs and
// lastWriteAgoMs move with now, so a live session changes the report on every poll. Each call keeps its own baseline.
// emit runs on the calling goroutine, so a slow emit delays the next poll rather than overlapping it. Watch returns
// ctx.Err() when ctx ends, and reads nothing after that.
func (s *Service) Watch(ctx context.Context, interval time.Duration, emit func(Report)) error {
	report, err := s.Read(ctx)
	if err != nil {
		return err
	}
	last, err := json.Marshal(report)
	if err != nil {
		return err
	}
	emit(report)
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
		report, err := s.Read(ctx)
		if err != nil {
			return err
		}
		encoded, err := json.Marshal(report)
		if err != nil {
			return err
		}
		if !bytes.Equal(encoded, last) {
			last = encoded
			emit(report)
		}
	}
}

// Stop ends the running session cli/id; see Stop. It never takes a pid.
func (s *Service) Stop(ctx context.Context, cli CLI, id string) (StopResult, error) {
	return Stop(ctx, s.roots, cli, id, s.proc, DefaultStopOptions())
}
