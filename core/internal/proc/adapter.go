// Package proc is the only place Activity touches the operating system: process lookup, start
// times, Codex thread locks and SIGTERM for Stop. Ported from Sources/ReinsCore/ProcessAdapter.swift
// and Sources/Reins/Activity/FixtureProcessAdapter.swift.
//
// Only Terminate changes anything. The real adapter exists on darwin (ps, lsof, kill(2)); every other
// OS gets an adapter that reports "not measurable on this OS" without failing. The fixture adapter
// replays a process list from a file and exists only under SPACEVIBE_TEST=1 (see New).
package proc

import (
	"context"
	"errors"
	"fmt"
	"math"
	"syscall"
)

// Thread is a live codex process and the thread it holds a writer lock on. ThreadID is empty before
// the first prompt (the Swift optional is nil there; a real thread id is never empty).
type Thread struct {
	Pid      int
	ThreadID string
	// LockUnknown is true when the lock listing (lsof) failed, so ThreadID being empty does not mean "no
	// thread yet": the process may hold one. Callers must not treat such a row as thread-less.
	LockUnknown bool
}

// Identity is what one reading of the process table says about a pid: the `ps lstart` text and the
// executable's basename. Two readings of the same process are equal; a reused pid differs in Start.
type Identity struct {
	Start string
	Name  string
}

// Adapter is the process view Activity uses. Tests pass a fake with the same shape.
type Adapter interface {
	// Measurable reports whether this adapter can see processes at all.
	Measurable() bool
	// IsAlive is true when a signal 0 to pid is delivered or refused for permission.
	IsAlive(ctx context.Context, pid int) bool
	// StartTime is the UTC `ps lstart` text, the same format as a Claude status file's procStart.
	// ok is false when it is unknown.
	StartTime(ctx context.Context, pid int) (start string, ok bool)
	// Identify reads the start time and executable name of pid in one reading, so Stop can bind its
	// decision to one process generation and read it again right before the signal. It returns
	// ErrNoSuchProcess when ps shows no such pid, ErrUnknown when the reading failed (ps missing, timed
	// out, unparsable), and ErrNotMeasurable on an OS where processes cannot be read.
	Identify(ctx context.Context, pid int) (Identity, error)
	// CodexThreads lists the live codex processes with the thread each one holds a lock on. The error is
	// ErrUnknown when the process list itself could not be read (the list is then not "empty": it is
	// unknown). When only the lock listing failed, the processes are returned with LockUnknown set.
	CodexThreads(ctx context.Context) ([]Thread, error)
	// Terminate sends SIGTERM. It returns ErrNoSuchProcess, ErrNotPermitted, a SignalError, or
	// ErrNotMeasurable.
	Terminate(ctx context.Context, pid int) error
}

// Why Terminate failed. ErrNoSuchProcess is ESRCH and ErrNotPermitted is EPERM.
var (
	ErrNoSuchProcess = errors.New("no such process")
	ErrNotPermitted  = errors.New("operation not permitted")
	// ErrNotMeasurable is what an adapter on an unsupported OS returns where an answer was needed.
	ErrNotMeasurable = errors.New("not measurable on this OS")
	// ErrUnknown means a ps or lsof reading failed or timed out, so the answer is unknown, never "empty".
	ErrUnknown = errors.New("process state unknown")
)

// SignalError is any other errno from kill(2).
type SignalError struct{ Errno syscall.Errno }

func (e SignalError) Error() string { return fmt.Sprintf("signal failed with errno %d", int(e.Errno)) }

// validPid guards every pid before it reaches kill: kill(0, sig) signals the caller's whole process
// group and kill(-1, sig) every process the user may signal.
func validPid(pid int) bool { return pid > 0 && int64(pid) <= math.MaxInt32 }
