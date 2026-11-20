package activity

import (
	"errors"
	"io/fs"
	"math"
	"os"
	"sort"
	"strings"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/textjs"
)

// Claude Code sessions: one row per status file in <root>/sessions, checked against the process table.

type claudeLiveSession struct {
	status    jv
	pid       int
	sessionID string
	alive     bool
	main      *logFile
	subs      []logFile
}

func claudeState(alive bool, status string, st *logState, lastWriteAgoMs, toolQuietMs float64) stateInfo {
	if !alive {
		return stateInfo{state: StateEnded, text: "The process has exited."}
	}
	tool := lastPending(st)
	switch {
	case status == "idle":
		return stateInfo{state: StateIdle, text: "Turn finished, waiting for the next prompt."}
	case status == "shell":
		return stateInfo{state: StateRunning, text: "Running a shell command.", tool: tool}
	case status != "busy":
		return unmeasurable(ReasonClaudeUnknownStatus, nil)
	case hasQuestions(st):
		return stateInfo{state: StateWaiting, text: "Waiting for your answer to a question.", tool: tool}
	case tool != nil && lastWriteAgoMs > toolQuietMs:
		return unmeasurable(claudeApprovalLimit, tool)
	}
	return stateInfo{state: StateRunning, text: toolText(tool), tool: tool}
}

// claudeSessions is one row per Claude status file, ended sessions older than EndedKeepMs dropped.
func claudeSessions(live []claudeLiveSession, rc *readContext) []Session {
	var sessions []Session
	for _, c := range live {
		var entry *cacheEntry
		if c.main != nil {
			entry = rc.foldedByPath[c.main.path]
		}
		var st *logState
		if entry != nil {
			st = entry.state
		}
		newestWrite := 0.0
		if c.main != nil {
			newestWrite = c.main.mtimeMs
		}
		for _, f := range c.subs {
			newestWrite = math.Max(newestWrite, f.mtimeMs)
		}
		written := nowFallback(newestWrite, c, rc.nowMs)
		lastWriteAgoMs := math.Max(0, rc.nowMs-written)
		if !c.alive && lastWriteAgoMs > rc.opts.EndedKeepMs {
			continue
		}
		var startedAt *float64
		if d, ok := c.status.field("startedAt").number(); ok {
			if b, ok := textjs.BoundedTimestamp(d); ok {
				startedAt = &b
			}
		}
		if startedAt == nil && st != nil && st.startedAtSet {
			if b, ok := textjs.BoundedTimestamp(st.startedAt); ok {
				startedAt = &b
			}
		}
		var subEntries []*cacheEntry
		for _, f := range c.subs[:min(len(c.subs), maxSubagentLogs)] {
			if e := rc.foldedByPath[f.path]; e != nil {
				subEntries = append(subEntries, e)
			}
		}
		nameSource, _ := c.status.field("nameSource").str()
		statusText, _ := c.status.field("status").str()
		state := claudeState(c.alive, statusText, st, lastWriteAgoMs, rc.opts.ToolQuietMs)
		var cost *Cost
		var costNote *string
		if entry != nil {
			cost, costNote = costFor(append([]*cacheEntry{entry}, subEntries...))
		} else if c.main != nil && rc.unreadable[c.main.path] {
			costNote = strPtr(transcriptUnreadable)
		} else {
			costNote = strPtr(noTranscript)
		}
		var custom, ai, first, hint string
		if st != nil {
			custom, ai, first, hint = st.customTitle, st.aiTitle, st.firstPrompt, st.worktreeOriginal
		}
		statusName := ""
		if nameSource != "derived" {
			statusName, _ = c.status.field("name").str()
		}
		cwd, ok := c.status.field("cwd").str()
		if !ok && st != nil {
			cwd = st.cwd
		}
		var project *string
		if p, ok := projectName(cwd, hint, rc.memo); ok {
			project = &p
		}
		var age *float64
		if d, ok := truthyPtr(startedAt); ok {
			a := math.Max(0, rc.nowMs-d)
			age = &a
		}
		sessions = append(sessions, Session{
			CLI: clis.Claude, ID: c.sessionID, Title: pickTitle([]string{custom, ai, statusName, first}, startedAt, c.sessionID),
			Project: project, Pid: c.pid, State: state.state, StateReason: state.text, ReasonCode: state.reason, CurrentTool: state.tool,
			AgeMs: age, LastWriteAgoMs: &lastWriteAgoMs, Cost: cost, CostNote: costNote,
		})
	}
	return sessions
}

// nowFallback is `newestWrite != 0 ? newestWrite : (statusUpdatedAt || startedAt || now)`.
func nowFallback(newestWrite float64, c claudeLiveSession, nowMs float64) float64 {
	if newestWrite != 0 {
		return newestWrite
	}
	if d, ok := truthyNumber(c.status.field("statusUpdatedAt")); ok {
		return d
	}
	if d, ok := truthyNumber(c.status.field("startedAt")); ok {
		return d
	}
	return nowMs
}

// isStatusFileName is `<digits>.json`.
func isStatusFileName(name string) bool {
	if !strings.HasSuffix(name, ".json") || len(name) <= 5 {
		return false
	}
	for _, c := range []byte(name[:len(name)-5]) {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// statusFileNames lists the Claude status files (`<pid>.json`) of a sessions folder, sorted.
func statusFileNames(dir string) []string {
	names, _ := listStatusFiles(dir)
	return names
}

// listStatusFiles is statusFileNames with the read error. A folder that does not exist is no error (nothing is
// running); one that cannot be read (permissions, I/O) is, because then "no status file" proves nothing.
func listStatusFiles(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if isStatusFileName(e.Name()) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}
