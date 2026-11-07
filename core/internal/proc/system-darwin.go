//go:build darwin

package proc

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	psPath       = "/bin/ps"
	lsofPath     = "/usr/sbin/lsof"
	startTimeout = 3 * time.Second
	listTimeout  = 5 * time.Second
	// killGrace bounds how long Wait lingers on pipes a killed tool's children may still hold.
	killGrace = 500 * time.Millisecond
)

// System is the real adapter: ps and lsof through os/exec, kill(2) for the signals. It reads only,
// except Terminate.
type System struct {
	// ps and lsof override the tool paths; tests point them at stand-ins. Empty means psPath and lsofPath.
	ps, lsof string
}

// NewSystem returns the real adapter.
func NewSystem() System { return System{} }

// Measurable is true on darwin.
func (System) Measurable() bool { return true }

// IsAlive sends signal 0; a permission error still means the process exists.
func (System) IsAlive(_ context.Context, pid int) bool {
	if !validPid(pid) {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}

// StartTime is `ps -o lstart= -p pid` under TZ=UTC, trimmed; not ok when ps fails or prints nothing.
func (s System) StartTime(ctx context.Context, pid int) (string, bool) {
	if !validPid(pid) {
		return "", false
	}
	res, ok := run(ctx, orDefault(s.ps, psPath), []string{"-o", "lstart=", "-p", strconv.Itoa(pid)}, startTimeout)
	if !ok || res.status != 0 {
		return "", false
	}
	text := strings.TrimSpace(res.stdout)
	return text, text != ""
}

// Identify is `ps -o lstart=,comm= -p pid` under TZ=UTC: one reading gives the start time and the
// executable basename. ps exits 1 with no output for a pid that does not exist; any other failure (cannot
// start, timeout, odd status, unparsable text) is ErrUnknown, never "no such process".
func (s System) Identify(ctx context.Context, pid int) (Identity, error) {
	if !validPid(pid) {
		return Identity{}, ErrNoSuchProcess
	}
	res, ok := run(ctx, orDefault(s.ps, psPath), []string{"-o", "lstart=", "-o", "comm=", "-p", strconv.Itoa(pid)}, startTimeout)
	if !ok || (res.status != 0 && res.status != 1) {
		return Identity{}, ErrUnknown
	}
	text := strings.TrimSpace(res.stdout)
	if text == "" && res.status == 1 {
		return Identity{}, ErrNoSuchProcess
	}
	id, parsed := ParseIdentity(text)
	if !parsed {
		return Identity{}, ErrUnknown
	}
	return id, nil
}

// CodexThreads lists live codex processes with the thread lock each holds. A failed or timed out `ps`
// is ErrUnknown. A failed `lsof` keeps the processes but marks each LockUnknown: without the lock listing a
// process that holds a thread cannot be told from one that has none yet.
func (s System) CodexThreads(ctx context.Context) ([]Thread, error) {
	ps, ok := run(ctx, orDefault(s.ps, psPath), []string{"-axo", "pid=,args="}, listTimeout)
	if !ok || ps.status != 0 {
		return nil, ErrUnknown
	}
	pids := CodexPids(ps.stdout)
	if len(pids) == 0 {
		return nil, nil
	}
	list := make([]string, len(pids))
	for i, p := range pids {
		list[i] = strconv.Itoa(p)
	}
	lsof, ran := run(ctx, orDefault(s.lsof, lsofPath), []string{"-nP", "-Fpn", "-p", strings.Join(list, ",")}, listTimeout)
	if !ran || !LsofUsable(lsof.status, lsof.stdout) {
		threads := make([]Thread, len(pids))
		for i, p := range pids {
			threads[i] = Thread{Pid: p, LockUnknown: true}
		}
		return threads, nil
	}
	return MergeThreads(pids, LockFds(lsof.stdout)), nil
}

func orDefault(path, fallback string) string {
	if path != "" {
		return path
	}
	return fallback
}

// Terminate sends SIGTERM to a pid that passed the guard.
func (System) Terminate(_ context.Context, pid int) error {
	if !validPid(pid) {
		return ErrNoSuchProcess
	}
	err := syscall.Kill(pid, syscall.SIGTERM)
	if err == nil {
		return nil
	}
	switch {
	case errors.Is(err, syscall.ESRCH):
		return ErrNoSuchProcess
	case errors.Is(err, syscall.EPERM):
		return ErrNotPermitted
	}
	var errno syscall.Errno
	errors.As(err, &errno)
	return SignalError{Errno: errno}
}

type output struct {
	stdout string
	status int
}

// run executes a tool by argv (no shell) with TZ=UTC and LC_ALL=C (ps prints its start time in UTC,
// which is how Claude writes procStart). ok is false when it cannot start. A tool that outlives timeout,
// or whose ctx ends, is killed and its output so far is returned with a non-zero status.
func run(ctx context.Context, path string, args []string, timeout time.Duration) (output, bool) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, args...)
	cmd.Env = append(os.Environ(), "TZ=UTC", "LC_ALL=C")
	var out bytes.Buffer
	cmd.Stdout = &out // Stdin and Stderr stay nil: /dev/null
	cmd.WaitDelay = killGrace
	if err := cmd.Start(); err != nil {
		return output{}, false
	}
	_ = cmd.Wait()
	return output{stdout: out.String(), status: cmd.ProcessState.ExitCode()}, true
}
