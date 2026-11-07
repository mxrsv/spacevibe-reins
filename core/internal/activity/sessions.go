package activity

import (
	"context"
	"math"
	"path/filepath"
	"sort"
	"strconv"

	"spacevibe.dev/core/internal/logs"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// The session rows of Activity.swift: Claude status files checked against the process table, and the Codex threads
// that live processes hold.

type claudeLiveSession struct {
	status    jv
	pid       int
	sessionID string
	alive     bool
	main      *logFile
	subs      []logFile
}

// stateInfo is a session state with the sentence that explains it.
type stateInfo struct {
	state  SessionState
	reason *Reason
	text   string
	tool   *Tool
}

func unmeasurable(code Reason, tool *Tool) stateInfo {
	return stateInfo{state: StateUnmeasurable, reason: &code, text: code.Text(), tool: tool}
}

func lastPending(st *logState) *Tool {
	if st == nil {
		return nil
	}
	p, ok := st.pending.Last()
	if !ok {
		return nil
	}
	return &Tool{Name: p.name, Target: p.target}
}

func hasQuestions(st *logState) bool { return st != nil && len(st.questions) > 0 }

func toolText(tool *Tool) string {
	if tool != nil {
		return "A tool call is open."
	}
	return "Turn in progress."
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
		return unmeasurable(ReasonClaudePromptVsBusy, tool)
	}
	return stateInfo{state: StateRunning, text: toolText(tool), tool: tool}
}

func codexState(st *logState, lastWriteAgoMs, toolQuietMs float64) stateInfo {
	tool := lastPending(st)
	if st.status == "busy" {
		switch {
		case len(st.questions) > 0:
			return stateInfo{state: StateWaiting, text: "Waiting for your answer to a question.", tool: tool}
		case tool != nil && lastWriteAgoMs > toolQuietMs:
			return unmeasurable(ReasonCodexToolSilent, tool)
		}
		return stateInfo{state: StateRunning, text: toolText(tool), tool: tool}
	}
	text := "No turn recorded yet."
	if st.status == "idle" {
		text = "Turn finished or aborted, waiting for the next prompt."
	}
	return stateInfo{state: StateIdle, text: text}
}

// liveProcesses reads the Claude status files, checks each against the process table, and lists the Codex threads
// that live processes hold. codexUnknown is true when the process list itself could not be read: the Codex list is
// then unknown, not empty.
func liveProcesses(ctx context.Context, r roots.Roots, index logIndex, adapter proc.Adapter) (live []claudeLiveSession, threads []proc.Thread, codexUnknown bool) {
	dir := filepath.Join(r.Claude.Root, "sessions")
	for _, name := range statusFileNames(dir) {
		s, ok := readJSONObject(filepath.Join(dir, name))
		if !ok {
			continue
		}
		pid, okPid := s.field("pid").integer()
		sessionID, okID := s.field("sessionId").str()
		if !okPid || !okID {
			continue
		}
		alive := adapter.IsAlive(ctx, pid)
		if procStart, ok := s.field("procStart").str(); alive && ok && procStart != "" {
			// A reused pid has a different start time; two readings that disagree mean another process.
			if started, ok := adapter.StartTime(ctx, pid); ok && started != "" && textjs.Collapse(started) != textjs.Collapse(procStart) {
				alive = false
			}
		}
		subs := append([]logFile(nil), index.claudeSubs[sessionID]...)
		sort.SliceStable(subs, func(i, j int) bool { return subs[i].mtimeMs > subs[j].mtimeMs })
		c := claudeLiveSession{status: s, pid: pid, sessionID: sessionID, alive: alive, subs: subs}
		if main, ok := index.claudeMain[sessionID]; ok {
			c.main = &main
		}
		live = append(live, c)
	}
	threads, err := adapter.CodexThreads(ctx)
	return live, threads, err != nil
}

// truthyNumber is a JSON number that is non-zero and inside the date range (a JavaScript `||` chain).
func truthyNumber(v jv) (float64, bool) {
	d, ok := v.number()
	if !ok {
		return 0, false
	}
	return truthy(d, true)
}

func truthy(d float64, ok bool) (float64, bool) {
	if !ok {
		return 0, false
	}
	bounded, ok := textjs.BoundedTimestamp(d)
	if !ok || bounded == 0 {
		return 0, false
	}
	return bounded, true
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
			CLI: CLIClaude, ID: c.sessionID, Title: pickTitle([]string{custom, ai, statusName, first}, startedAt, c.sessionID),
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

func truthyPtr(p *float64) (float64, bool) {
	if p == nil {
		return 0, false
	}
	return truthy(*p, true)
}

// codexSessions is one row per live `codex` process; a child rollout, or a thread-less row whose pid already holds
// a thread, gets none.
func codexSessions(ctx context.Context, threads []proc.Thread, rc *readContext) []Session {
	var sessions []Session
	names := codexThreadNames(rc.roots)
	for _, t := range threads {
		var file *logFile
		var entry *cacheEntry
		if t.ThreadID != "" {
			if f, ok := rc.index.codexByID[t.ThreadID]; ok {
				file = &f
				entry = rc.foldedByPath[f.path]
			}
		}
		if t.ThreadID != "" && file != nil {
			child := false
			if logs.IsCompressed(file.path) {
				child = entry != nil && entry.state.parent
			} else {
				child = isChildRollout(file.path)
			}
			if child {
				continue
			}
		}
		if t.ThreadID == "" && rc.codexPids[t.Pid] {
			continue
		}
		if t.LockUnknown {
			sessions = append(sessions, codexWithoutRollout(ctx, t, names, rc))
			continue
		}
		if file == nil || entry == nil {
			row := codexWithoutRollout(ctx, t, names, rc)
			if file != nil && rc.unreadable[file.path] {
				row = codexUnreadableRollout(row)
			}
			sessions = append(sessions, row)
			continue
		}
		lastWriteAgoMs := math.Max(0, rc.nowMs-file.mtimeMs)
		st := entry.state
		state := codexState(st, lastWriteAgoMs, rc.opts.ToolQuietMs)
		cost, costNote := costFor([]*cacheEntry{entry})
		var startedAt *float64
		if st.startedAtSet {
			startedAt = &st.startedAt
		}
		var project *string
		if p, ok := projectName(st.cwd, "", rc.memo); ok {
			project = &p
		}
		var age *float64
		if d, ok := truthyPtr(startedAt); ok {
			a := math.Max(0, rc.nowMs-d)
			age = &a
		}
		sessions = append(sessions, Session{
			CLI: CLICodex, ID: t.ThreadID, Title: pickTitle([]string{names[t.ThreadID], st.firstPrompt}, startedAt, t.ThreadID),
			Project: project, Pid: t.Pid, State: state.state, StateReason: state.text, ReasonCode: state.reason, CurrentTool: state.tool,
			AgeMs: age, LastWriteAgoMs: &lastWriteAgoMs, Cost: cost, CostNote: costNote,
		})
	}
	return sessions
}

// codexWithoutRollout is the row of a Codex process whose rollout does not exist yet, so the process start is the
// only clock. When the lock listing failed (t.LockUnknown) the row says so instead: the thread, and so the rollout,
// is not known, and the id is the `:unknown` form that cannot authorize Stop.
func codexWithoutRollout(ctx context.Context, t proc.Thread, names map[string]string, rc *readContext) Session {
	processStart, hasStart := rc.proc.StartTime(ctx, t.Pid)
	var startedAt *float64
	if hasStart {
		if ms, ok := textjs.ParseProcessStart(processStart); ok {
			startedAt = &ms
		}
	}
	id := t.ThreadID
	titleID := t.ThreadID
	if t.ThreadID == "" {
		var ok bool
		if id, ok = codexProcessID(t.Pid, processStart, hasStart); !ok {
			id = "pid:" + strconv.Itoa(t.Pid) + ":unknown"
		}
		titleID = "pid " + strconv.Itoa(t.Pid)
	}
	var age *float64
	if startedAt != nil {
		a := math.Max(0, rc.nowMs-*startedAt)
		age = &a
	}
	reason := ReasonCodexNoRollout
	if t.LockUnknown {
		reason = ReasonCodexProcessUnknown
		id = "pid:" + strconv.Itoa(t.Pid) + ":unknown"
	}
	return Session{
		CLI: CLICodex, ID: id, Title: pickTitle([]string{names[t.ThreadID]}, startedAt, titleID),
		Pid: t.Pid, State: StateUnmeasurable, StateReason: reason.Text(), ReasonCode: &reason,
		AgeMs: age, CostNote: strPtr(reason.Text()),
	}
}

// codexUnreadableRollout turns the no-rollout row of a thread whose rollout exists into the unreadable one: same id,
// title and clock, its own reason.
func codexUnreadableRollout(row Session) Session {
	reason := ReasonCodexRolloutUnreadable
	row.StateReason, row.ReasonCode, row.CostNote = reason.Text(), &reason, strPtr(reason.Text())
	return row
}

func isCompressedLog(path string) bool {
	return filepath.Ext(path) == ".zst" || filepath.Ext(path) == ".zstd"
}
