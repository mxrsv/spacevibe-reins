package activity

import (
	"bytes"
	"context"
	"io"
	"math"
	"os"
	"path/filepath"
	"strconv"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/logs"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// Codex sessions: one row per live codex process, matched to its rollout through the thread lock it holds.

func codexState(st *logState, lastWriteAgoMs, toolQuietMs float64) stateInfo {
	tool := lastPending(st)
	if st.status == "busy" {
		switch {
		case len(st.questions) > 0:
			return stateInfo{state: StateWaiting, text: "Waiting for your answer to a question.", tool: tool}
		case tool != nil && lastWriteAgoMs > toolQuietMs:
			return unmeasurable(codexApprovalLimit, tool)
		}
		return stateInfo{state: StateRunning, text: toolText(tool), tool: tool}
	}
	text := "No turn recorded yet."
	if st.status == "idle" {
		text = "Turn finished or aborted, waiting for the next prompt."
	}
	return stateInfo{state: StateIdle, text: text}
}

// codexSessions is one row per live `codex` process; a child rollout, or a thread-less row whose pid already holds
// a thread, gets none.
func codexSessions(ctx context.Context, c *codexRead, rc *readContext) []Session {
	var sessions []Session
	names := codexThreadNames(c.root)
	// pids that hold a thread: a thread-less row of the same pid is not listed again.
	threadPids := map[int]bool{}
	for _, t := range c.threads {
		if t.ThreadID != "" {
			threadPids[t.Pid] = true
		}
	}
	for _, t := range c.threads {
		var file *logFile
		var entry *cacheEntry
		if t.ThreadID != "" {
			if f, ok := c.byID[t.ThreadID]; ok {
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
		if t.ThreadID == "" && threadPids[t.Pid] {
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
			CLI: clis.Codex, ID: t.ThreadID, Title: pickTitle([]string{names[t.ThreadID], st.firstPrompt}, startedAt, t.ThreadID),
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
		CLI: clis.Codex, ID: id, Title: pickTitle([]string{names[t.ThreadID]}, startedAt, titleID),
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

// threadID is the uuid that ends a rollout's name: `rollout-2026-11-02T09-00-01-<uuid>.jsonl[.zst]`. Swift took the
// last 36 Characters; this takes the last 36 bytes, which is the same for the ASCII-only uuid shape.
func threadID(path string) (string, bool) {
	base := logs.BaseName(path)
	if len(base) < 36 {
		return "", false
	}
	tail := base[len(base)-36:]
	for i := 0; i < 36; i++ {
		c := tail[i]
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return "", false
			}
		} else if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return "", false
		}
	}
	return tail, true
}

// isChildRollout: Codex subagent rollouts name their parent thread in session_meta (the first 64 KB is enough).
func isChildRollout(path string) bool {
	head := readHead(path, childHeadBytes)
	if textjs.Contains(head, `"source":{"subagent"`) {
		return true
	}
	key := []byte(`"parent_thread_id":"`)
	// The Swift loop stops one byte early (i + key.count < bytes.count), so a key at the very end never counts.
	for i := 0; i+len(key) < len(head); i++ {
		if head[i] == key[0] && bytes.Equal(head[i:i+len(key)], key) {
			c := head[i+len(key)]
			if (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') {
				return true
			}
		}
	}
	return false
}

// codexThreadNames reads thread names from the tail of the session index; a later line wins.
func codexThreadNames(cli roots.CLIRoots) map[string]string {
	names := map[string]string{}
	path := filepath.Join(cli.Root, "session_index.jsonl")
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() {
		return names
	}
	f, err := os.Open(path)
	if err != nil {
		return names
	}
	defer f.Close()
	size := info.Size()
	start := int64(0)
	if size > indexTailBytes {
		start = size - indexTailBytes
	}
	data, err := io.ReadAll(io.NewSectionReader(f, start, size-start))
	if err != nil {
		return names
	}
	lines := bytes.Split(data, []byte{'\n'})
	if start > 0 && len(lines) > 0 {
		lines = lines[1:]
	}
	for _, line := range lines {
		doc, err := ojson.Parse(line)
		if err != nil {
			continue
		}
		root := present(doc.Root())
		id, ok := root.field("id").str()
		if !ok || id == "" {
			continue
		}
		if name, ok := root.field("thread_name").str(); ok {
			names[id] = name
		}
	}
	return names
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
