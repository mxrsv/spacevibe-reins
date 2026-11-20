package activity

import (
	"context"
	"errors"
	"strconv"
	"time"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// ActivityStop.swift: ends one running session (SIGTERM). It cannot be undone: the current turn stops, finished
// work stays. The engine never asks the user; the UI confirms before it calls this.

// StopResult is what Stop found out. Exited is false when the process was still alive at the end of the wait.
type StopResult struct {
	Exited bool `json:"exited"`
}

// StopOptions set how long Stop waits for the process to go away after the signal.
type StopOptions struct {
	Wait time.Duration
	Poll time.Duration
}

// DefaultStopOptions waits up to 3 s, polling every 100 ms.
func DefaultStopOptions() StopOptions {
	return StopOptions{Wait: 3 * time.Second, Poll: 100 * time.Millisecond}
}

func sameStart(a string, aOK bool, b string, bOK bool) bool {
	return aOK && bOK && a != "" && b != "" && textjs.Collapse(a) == textjs.Collapse(b)
}

// lookup is what livePid found. found is the process (pid and the identity read in the same snapshot as the pid).
// unverified is true when some candidate or source could not be read, so "not found" does not prove the session is
// gone: Stop then says it cannot verify instead of "no longer running".
type lookup struct {
	pid        int
	identity   proc.Identity
	found      bool
	unverified bool
}

// livePid is the process of a live session, decided from the system now and never taken from the caller: pids get
// reused. Its identity (start time and name) is read once here and read again by Stop right before the signal. The
// session's CLI decides how (stopper); a CLI with no Activity adapter is an error, never looked up as another CLI.
func livePid(ctx context.Context, r roots.Roots, cli clis.ID, id string, adapter proc.Adapter) (lookup, error) {
	a, err := adapters.For(cli)
	if err != nil {
		return lookup{}, err
	}
	folders, err := r.CLI(cli)
	if err != nil {
		return lookup{}, err
	}
	return a.livePid(ctx, folders, id, adapter), nil
}

// startsComparable is true when both start times are in the `ps -o lstart=` spelling, so a difference means another process.
func startsComparable(live, recorded string, recordedOK bool) bool {
	if !recordedOK {
		return false
	}
	_, liveOK := textjs.ParseProcessStart(live)
	_, recordedParsed := textjs.ParseProcessStart(recorded)
	return liveOK && recordedParsed
}

var (
	errNoLongerRunning = coreerr.NewStatus("That session is no longer running.", coreerr.StatusNotFound)
	errCannotVerify    = coreerr.NewStatus("That session could not be verified, so nothing was stopped.", coreerr.StatusConflict)
)

// Stop asks one running session to end. The process is looked up again from the live system (the Claude status file
// with its start time, or the Codex thread lock), and its start time and name are read once with the pid and read
// again immediately before the signal; if either differs the process is not the one looked up and nothing is sent.
// (Between that last read and kill(2) a pid could still be reused; the window is that of the two syscalls, and darwin
// has no pidfd to close it.)
//
// Errors are coreerr.Error: 404 when the session is no longer running, 409 when it cannot be verified (ps, lsof or
// the sessions folder could not be read, or the start time is unknown), 403 when it belongs to another user, 500 for
// any other signal error (and on an OS where processes cannot be measured). A cancelled ctx stops the wait for the
// process to exit but not the signal that was already sent; the result then says whether it had gone.
func Stop(ctx context.Context, r roots.Roots, cli clis.ID, id string, adapter proc.Adapter, opts StopOptions) (StopResult, error) {
	if !adapter.Measurable() {
		return StopResult{}, coreerr.NewStatus("Sessions cannot be stopped on this system.", coreerr.StatusInternalFailure)
	}
	found, err := livePid(ctx, r, cli, id, adapter)
	if err != nil {
		return StopResult{}, err
	}
	if !found.found {
		if found.unverified {
			return StopResult{}, errCannotVerify
		}
		return StopResult{}, errNoLongerRunning
	}
	pid := found.pid
	switch again, err := adapter.Identify(ctx, pid); {
	case errors.Is(err, proc.ErrNoSuchProcess):
		return StopResult{}, errNoLongerRunning
	case err != nil:
		return StopResult{}, errCannotVerify
	case again != found.identity:
		return StopResult{}, errNoLongerRunning
	}
	if err := adapter.Terminate(ctx, pid); err != nil {
		var signal proc.SignalError
		switch {
		case errors.Is(err, proc.ErrNoSuchProcess):
			return StopResult{Exited: true}, nil
		case errors.Is(err, proc.ErrNotPermitted):
			return StopResult{}, coreerr.NewStatus("This session belongs to another user, so it cannot be stopped.", coreerr.StatusForbidden)
		case errors.As(err, &signal):
			return StopResult{}, coreerr.NewStatus("The session could not be stopped (error "+strconv.Itoa(int(signal.Errno))+").", coreerr.StatusInternalFailure)
		default:
			return StopResult{}, coreerr.NewStatus("Sessions cannot be stopped on this system.", coreerr.StatusInternalFailure)
		}
	}
	deadline := time.Now().Add(opts.Wait)
	poll := max(opts.Poll, time.Millisecond)
	for time.Now().Before(deadline) {
		if !adapter.IsAlive(ctx, pid) {
			return StopResult{Exited: true}, nil
		}
		select {
		case <-ctx.Done():
			return StopResult{Exited: !adapter.IsAlive(context.WithoutCancel(ctx), pid)}, nil
		case <-time.After(poll):
		}
	}
	return StopResult{Exited: !adapter.IsAlive(context.WithoutCancel(ctx), pid)}, nil
}
