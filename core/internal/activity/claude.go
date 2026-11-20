package activity

import (
	"context"
	"errors"
	"io/fs"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/logs"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// claudeActivity is Claude Code's side of Activity: transcripts under projects/, one status file per running
// session under sessions/, and the status file's pid for Stop.
type claudeActivity struct{}

func (claudeActivity) fold(st *logState, line []byte) { foldClaude(st, line) }

func (claudeActivity) edits(st *logState) []editEvent { return st.edits }

func (claudeActivity) limits() []Reason { return []Reason{claudeApprovalLimit} }

// claudeApprovalLimit: Claude Code records no permission prompt, so claudeState reads a quiet tool run as this.
const claudeApprovalLimit = ReasonClaudePromptVsBusy

func (claudeActivity) approvalLimit() Reason { return claudeApprovalLimit }

// claudeRead is Claude Code's part of one Read.
type claudeRead struct {
	root roots.CLIRoots
	all  []logFile
	// main is the transcript of each session; subs its subagent logs.
	main map[string]logFile
	subs map[string][]logFile
	live []claudeLiveSession
}

// listLogs finds every transcript. A log is `<projects>/<folder>/<session>.jsonl`, a subagent log is
// `<projects>/<folder>/<session>/subagents/<file>`.
func (claudeActivity) listLogs(cli roots.CLIRoots) cliRead {
	c := &claudeRead{root: cli, main: map[string]logFile{}, subs: map[string][]logFile{}}
	for _, path := range logs.Walk(cli.Logs) {
		rel, err := filepath.Rel(cli.Logs, path)
		if err != nil {
			continue
		}
		parts := strings.Split(filepath.ToSlash(rel), "/")
		sub := len(parts) >= 4 && parts[2] == "subagents"
		session := logs.BaseName(path)
		if sub {
			session = parts[1]
		}
		mtime, ok := mtimeMs(path)
		if !ok {
			continue
		}
		file := logFile{path: path, cli: clis.Claude, session: session, sub: sub, mtimeMs: mtime}
		c.all = append(c.all, file)
		if sub {
			c.subs[session] = append(c.subs[session], file)
		} else if len(parts) == 2 {
			c.main[session] = file
		}
	}
	return c
}

func (c *claudeRead) files() []logFile { return c.all }

// findLive reads the status files and checks each against the process table.
func (c *claudeRead) findLive(ctx context.Context, adapter proc.Adapter) {
	dir := filepath.Join(c.root.Root, "sessions")
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
		subs := append([]logFile(nil), c.subs[sessionID]...)
		sort.SliceStable(subs, func(i, j int) bool { return subs[i].mtimeMs > subs[j].mtimeMs })
		session := claudeLiveSession{status: s, pid: pid, sessionID: sessionID, alive: alive, subs: subs}
		if main, ok := c.main[sessionID]; ok {
			session.main = &main
		}
		c.live = append(c.live, session)
	}
}

// livePaths are the transcript and the newest subagent logs of every status file.
func (c *claudeRead) livePaths() []string {
	var out []string
	for _, s := range c.live {
		if s.main != nil {
			out = append(out, s.main.path)
		}
		for _, f := range s.subs[:min(len(s.subs), maxSubagentLogs)] {
			out = append(out, f.path)
		}
	}
	return out
}

func (c *claudeRead) sessions(_ context.Context, rc *readContext) []Session {
	return claudeSessions(c.live, rc)
}

func (c *claudeRead) extraLimits() []Limit { return nil }

// livePid finds the session's status file in <root>/sessions and checks its pid against the process table: alive,
// and started when the file says.
func (claudeActivity) livePid(ctx context.Context, cli roots.CLIRoots, id string, adapter proc.Adapter) lookup {
	var out lookup
	dir := filepath.Join(cli.Root, "sessions")
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
		// The pid is alive and the file names this session. Two start times that both parse and differ prove a reused
		// pid (not this session). If either cannot be compared, the session may well be this process: never "gone".
		if !startsComparable(identity.Start, recorded, recordedOK) {
			out.unverified = true
		}
	}
	return out
}
