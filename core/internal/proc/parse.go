package proc

import (
	"regexp"
	"strconv"
	"strings"
)

// ICU (NSRegularExpression) and Go differ on three things these patterns touch: \s is the Unicode
// White_Space set, `.` stops at any line terminator, and `$` also matches before one final line
// terminator. The classes below spell the ICU sets out and finalTerminator handles `$`.
const (
	icuSpace = `\t\n\v\f\r \x{85}\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}`
	icuDot   = `[^\n\r\x{85}\x{2028}\x{2029}]`
)

var (
	// Swift: ^\s*(\d+)\s+(?:\S*/)?codex(?:\s+(.*))?$  (\d is ASCII here: a non-ASCII digit makes Int() fail and the line is skipped)
	psLine = regexp.MustCompile(`^[` + icuSpace + `]*([0-9]+)[` + icuSpace + `]+(?:[^` + icuSpace + `]*/)?codex(?:[` + icuSpace + `]+(` + icuDot + `*))?$`)
	// Swift: [\\/]thread-writer-locks[\\/]([0-9a-f]{8}-...-[0-9a-f]{12})\.lock$
	lockPath    = regexp.MustCompile(`[\\/]thread-writer-locks[\\/]([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.lock$`)
	helperWords = map[string]bool{"app-server": true, "mcp-server": true}
)

// finalTerminator drops one trailing line terminator, which ICU's `$` accepts before the end.
func finalTerminator(s string) string {
	if strings.HasSuffix(s, "\r\n") {
		return s[:len(s)-2]
	}
	for _, t := range []string{"\n", "\r", "\u0085", " ", " "} {
		if strings.HasSuffix(s, t) {
			return s[:len(s)-len(t)]
		}
	}
	return s
}

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
