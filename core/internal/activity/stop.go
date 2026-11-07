package activity

import (
	"context"
	"errors"
	"io/fs"
	"math"
	"path/filepath"
	"strconv"
	"strings"
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
// reused. Its identity (start time and name) is read once here and read again by Stop right before the signal.
func livePid(ctx context.Context, r roots.Roots, cli CLI, id string, adapter proc.Adapter) lookup {
	if cli == CLICodex {
		return livePidCodex(ctx, id, adapter)
	}
	var out lookup
	dir := filepath.Join(r.Claude.Root, "sessions")
	names, err := listStatusFiles(dir)
	if err != nil {
		return lookup{unverified: true}
	}
	for _, name := range names {
		data, err := readRegularFileErr(filepath.Join(dir, name))
		if err != nil {
			// A file that vanished or is no regular file is not a live status file; an unreadable one may be ours.
			if !errors.Is(err, fs.ErrNotExist) && !errors.Is(err, errNotRegular) {
				out.unverified = true
			}
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
		identity, err := adapter.Identify(ctx, pid)
		switch {
		case errors.Is(err, proc.ErrNoSuchProcess):
			continue
		case err != nil:
			out.unverified = true
			continue
		}
		recorded, recordedOK := root.field("procStart").str()
		if sameStart(identity.Start, true, recorded, recordedOK) {
			out.pid, out.identity, out.found = pid, identity, true
			return out
		}
	}
	return out
}

func livePidCodex(ctx context.Context, id string, adapter proc.Adapter) lookup {
	threads, err := adapter.CodexThreads(ctx)
	if err != nil {
		return lookup{unverified: true}
	}
	var out lookup
	for _, thread := range threads {
		// A thread-less process can only be asked for by its own `pid:<n>:` id, so other processes are not read.
		byProcess := thread.ThreadID == "" && strings.HasPrefix(id, "pid:"+strconv.Itoa(thread.Pid)+":")
		switch {
		case thread.LockUnknown:
			// Whether this process holds a thread is unknown, so it could be the one asked for.
			out.unverified = true
			continue
		case thread.ThreadID != "" && thread.ThreadID != id, thread.ThreadID == "" && !byProcess:
			continue
		}
		identity, err := adapter.Identify(ctx, thread.Pid)
		switch {
		case errors.Is(err, proc.ErrNoSuchProcess):
			continue
		case err != nil || identity.Start == "":
			out.unverified = true
			continue
		}
		if thread.ThreadID == "" {
			current, ok := codexProcessID(thread.Pid, identity.Start, true)
			if !ok {
				out.unverified = true
				continue
			}
			if current != id {
				continue
			}
		}
		return lookup{pid: thread.Pid, identity: identity, found: true}
	}
	return out
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
func Stop(ctx context.Context, r roots.Roots, cli CLI, id string, adapter proc.Adapter, opts StopOptions) (StopResult, error) {
	if !adapter.Measurable() {
		return StopResult{}, coreerr.NewStatus("Sessions cannot be stopped on this system.", coreerr.StatusInternalFailure)
	}
	found := livePid(ctx, r, cli, id, adapter)
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
