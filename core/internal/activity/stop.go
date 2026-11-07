package activity

import (
	"context"
	"errors"
	"math"
	"path/filepath"
	"strconv"
	"time"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/ojson"
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

// codexProcessID binds a thread-less Codex row to the observed process generation, never just its reusable pid.
// It is false when the pid is out of range or the start is unknown or malformed.
func codexProcessID(pid int, start string, hasStart bool) (string, bool) {
	if pid <= 0 || pid > math.MaxInt32 || !hasStart {
		return "", false
	}
	started, ok := textjs.ParseProcessStart(start)
	if !ok {
		return "", false
	}
	return "pid:" + strconv.Itoa(pid) + ":" + strconv.FormatInt(int64(started), 10), true
}

// livePid is the pid of a live session, decided from the system now and never taken from the caller: pids get reused.
func livePid(ctx context.Context, r roots.Roots, cli CLI, id string, adapter proc.Adapter) (int, bool) {
	if cli == CLICodex {
		for _, thread := range adapter.CodexThreads(ctx) {
			if thread.ThreadID != "" {
				if thread.ThreadID == id {
					return thread.Pid, true
				}
				continue
			}
			start, ok := adapter.StartTime(ctx, thread.Pid)
			if current, ok := codexProcessID(thread.Pid, start, ok); ok && current == id {
				return thread.Pid, true
			}
		}
		return 0, false
	}
	dir := filepath.Join(r.Claude.Root, "sessions")
	for _, name := range statusFileNames(dir) {
		data, ok := readRegularFile(filepath.Join(dir, name))
		if !ok {
			continue
		}
		doc, err := ojson.Parse(data)
		if err != nil {
			continue
		}
		root := present(doc.Root())
		sessionID, hasID := root.field("sessionId").str()
		if !hasID || sessionID != id {
			continue
		}
		// Int(numberText): "41001.0" and "1e3" are not pids here, though the read path accepts them.
		pidField := root.field("pid")
		pidText, isNumber := pidField.v.NumberText()
		if !pidField.ok || !isNumber {
			continue
		}
		pid64, err := strconv.ParseInt(pidText, 10, 64)
		if err != nil || !adapter.IsAlive(ctx, int(pid64)) {
			continue
		}
		pid := int(pid64)
		have, haveOK := adapter.StartTime(ctx, pid)
		recorded, recordedOK := root.field("procStart").str()
		if sameStart(have, haveOK, recorded, recordedOK) {
			return pid, true
		}
	}
	return 0, false
}

// Stop asks one running session to end. The pid is looked up again from the live system (the Claude status file with
// its start time, or the Codex thread lock), so a stale row cannot signal a reused pid.
//
// Errors are coreerr.Error: 404 when the session is no longer running, 403 when it belongs to another user, 500 for
// any other signal error (and on an OS where processes cannot be measured). A cancelled ctx stops the wait for the
// process to exit but not the signal that was already sent; the result then says whether it had gone.
func Stop(ctx context.Context, r roots.Roots, cli CLI, id string, adapter proc.Adapter, opts StopOptions) (StopResult, error) {
	pid, ok := livePid(ctx, r, cli, id, adapter)
	if !ok {
		return StopResult{}, coreerr.NewStatus("That session is no longer running.", coreerr.StatusNotFound)
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
