package proc

import (
	"context"
	"regexp"
	"strconv"
	"strings"
)

// Codex's process match: Codex sessions are found from the process table (interactive codex processes) and the
// thread-writer lock each one holds, read with ps and lsof.

// Thread is a live codex process and the thread it holds a writer lock on. ThreadID is empty before
// the first prompt (the Swift optional is nil there; a real thread id is never empty).
type Thread struct {
	Pid      int
	ThreadID string
	// LockUnknown is true when the lock listing (lsof) failed, so ThreadID being empty does not mean "no
	// thread yet": the process may hold one. Callers must not treat such a row as thread-less.
	LockUnknown bool
}

// CodexMatcher is Codex's process match. It is not part of Adapter: Codex's activity adapter asserts it from the
// Adapter it is handed (activity.codexMatcher), and an adapter without it reads as the concept absent.
type CodexMatcher interface {
	// CodexThreads lists the live codex processes with the thread each one holds a lock on. The error is
	// ErrUnknown when the process list itself could not be read (the list is then not "empty": it is
	// unknown). When only the lock listing failed, the processes are returned with LockUnknown set.
	CodexThreads(ctx context.Context) ([]Thread, error)
}

// Every real adapter carries the Codex match.
var (
	_ CodexMatcher = System{}
	_ CodexMatcher = (*Fixture)(nil)
)

var (
	// Swift: ^\s*(\d+)\s+(?:\S*/)?codex(?:\s+(.*))?$  (\d is ASCII here: a non-ASCII digit makes Int() fail and the line is skipped)
	psLine = regexp.MustCompile(`^[` + icuSpace + `]*([0-9]+)[` + icuSpace + `]+(?:[^` + icuSpace + `]*/)?codex(?:[` + icuSpace + `]+(` + icuDot + `*))?$`)
	// Swift: [\\/]thread-writer-locks[\\/]([0-9a-f]{8}-...-[0-9a-f]{12})\.lock$
	lockPath    = regexp.MustCompile(`[\\/]thread-writer-locks[\\/]([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.lock$`)
	helperWords = map[string]bool{"app-server": true, "mcp-server": true}
)

// CodexPids reads `ps -axo pid=,args=` output into the pids of interactive-looking codex processes
// (app-server and mcp-server are helpers).
func CodexPids(psOutput string) []int {
	var pids []int
	for _, line := range strings.Split(psOutput, "\n") {
		m := psLine.FindStringSubmatch(finalTerminator(line))
		if m == nil {
			continue
		}
		pid, err := strconv.Atoi(m[1])
		if err != nil {
			continue
		}
		isHelper := false
		for _, w := range strings.FieldsFunc(m[2], func(r rune) bool { return r == ' ' || r == '\t' }) {
			if helperWords[w] {
				isHelper = true
				break
			}
		}
		if !isHelper {
			pids = append(pids, pid)
		}
	}
	return pids
}

// MergeThreads returns the lock entries, then every other pid with no thread yet (before its first
// prompt a codex holds no lock). A pid that holds a lock appears only through its locks.
func MergeThreads(pids []int, locks []Thread) []Thread {
	held := make(map[int]bool, len(locks))
	out := make([]Thread, 0, len(locks)+len(pids))
	for _, l := range locks {
		held[l.Pid] = true
		out = append(out, l)
	}
	for _, p := range pids {
		if !held[p] {
			out = append(out, Thread{Pid: p})
		}
	}
	return out
}

// LockFds reads `lsof -Fpn` output into one entry per (pid, thread lock).
func LockFds(lsofOutput string) []Thread {
	var out []Thread
	pid, havePid := 0, false
	for _, line := range strings.Split(lsofOutput, "\n") {
		switch {
		case strings.HasPrefix(line, "p"):
			n, err := strconv.Atoi(line[1:])
			pid, havePid = n, err == nil
		case strings.HasPrefix(line, "n") && havePid:
			if m := lockPath.FindStringSubmatch(finalTerminator(line[1:])); m != nil {
				out = append(out, Thread{Pid: pid, ThreadID: m[1]})
			}
		}
	}
	return out
}

// LsofUsable says whether an lsof run can be trusted to list the locks of the pids asked about. lsof exits 1
// when some pids are gone yet still prints the others, so 0 and 1 are fine; a kill by timeout or signal
// (status -1), any other status, or no output at all (not even the `p<pid>` line every live process gets) is
// a failed or empty look, which the caller reports as unknown.
func LsofUsable(status int, stdout string) bool {
	return (status == 0 || status == 1) && strings.TrimSpace(stdout) != ""
}
