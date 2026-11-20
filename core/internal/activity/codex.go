package activity

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/logs"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// codexActivity is Codex's side of Activity: rollouts under sessions/, the live codex processes and the thread lock
// each holds (proc.CodexMatcher, asserted from the process adapter), and that lock again for Stop.
type codexActivity struct{}

func (codexActivity) fold(st *logState, line []byte) { foldCodex(st, line) }

// edits prefers FileChange items over the older tool-text patches, whose relative paths are joined to the cwd.
func (codexActivity) edits(st *logState) []editEvent {
	if st.sawFileChange {
		return st.edits
	}
	base := st.cwd
	out := make([]editEvent, len(st.legacyEdits))
	for i, e := range st.legacyEdits {
		if strings.HasPrefix(e.path, "/") || base == "" {
			out[i] = e
			continue
		}
		out[i] = editEvent{id: e.id, path: strings.TrimSuffix(base, "/") + "/" + e.path, at: e.at}
	}
	return out
}

func (codexActivity) limits() []Reason {
	return []Reason{codexApprovalLimit, ReasonCodexNoRollout, ReasonCodexHookRuns}
}

// codexApprovalLimit: Codex logs nothing while a tool runs, so codexState reads a quiet tool run as this.
const codexApprovalLimit = ReasonCodexToolSilent

func (codexActivity) approvalLimit() Reason { return codexApprovalLimit }

// codexRead is Codex's part of one Read.
type codexRead struct {
	root roots.CLIRoots
	all  []logFile
	byID map[string]logFile
	// threads are the live codex processes; unknown is true when the process list could not be read, so the list
	// is unknown, not empty.
	threads []proc.Thread
	unknown bool
}

// listLogs finds every rollout; a rollout name ends in the thread uuid.
func (codexActivity) listLogs(cli roots.CLIRoots) cliRead {
	c := &codexRead{root: cli, byID: map[string]logFile{}}
	for _, path := range logs.Walk(cli.Logs) {
		if !strings.HasPrefix(filepath.Base(path), "rollout-") {
			continue
		}
		id, ok := threadID(path)
		if !ok {
			continue
		}
		mtime, ok := mtimeMs(path)
		if !ok {
			continue
		}
		file := logFile{path: path, cli: clis.Codex, session: id, mtimeMs: mtime}
		c.all = append(c.all, file)
		c.byID[id] = file
	}
	return c
}

func (c *codexRead) files() []logFile { return c.all }

// codexMatcher is the Codex match of the process adapter, or an error wrapping clis.ErrConceptAbsent when the adapter
// has none. Every real adapter has one; a missing match reads as an unknown process list, never as no sessions.
func codexMatcher(adapter proc.Adapter) (proc.CodexMatcher, error) {
	m, ok := adapter.(proc.CodexMatcher)
	if !ok {
		return nil, fmt.Errorf("%w: the process adapter has no %s process match", clis.ErrConceptAbsent, clis.Codex)
	}
	return m, nil
}

// codexThreads lists the live codex processes through the adapter's Codex match.
func codexThreads(ctx context.Context, adapter proc.Adapter) ([]proc.Thread, error) {
	m, err := codexMatcher(adapter)
	if err != nil {
		return nil, err
	}
	return m.CodexThreads(ctx)
}

func (c *codexRead) findLive(ctx context.Context, adapter proc.Adapter) {
	threads, err := codexThreads(ctx, adapter)
	c.threads, c.unknown = threads, err != nil
}

// livePaths are the rollouts of the threads live processes hold.
func (c *codexRead) livePaths() []string {
	var out []string
	for _, t := range c.threads {
		if f, ok := c.byID[t.ThreadID]; ok && t.ThreadID != "" {
			out = append(out, f.path)
		}
	}
	return out
}

func (c *codexRead) sessions(ctx context.Context, rc *readContext) []Session {
	return codexSessions(ctx, c, rc)
}

// extraLimits: when ps failed the Codex rows cannot be listed at all, so the report says that instead of showing
// none.
func (c *codexRead) extraLimits() []Limit {
	if !c.unknown {
		return nil
	}
	return []Limit{{CLI: clis.Codex, Code: ReasonCodexProcessUnknown, Text: ReasonCodexProcessUnknown.Text()}}
}

// livePid finds the codex process that holds the session's thread lock, or, for a thread-less row, the process its
// `pid:<n>:<start>` id names.
func (codexActivity) livePid(ctx context.Context, _ roots.CLIRoots, id string, adapter proc.Adapter) lookup {
	threads, err := codexThreads(ctx, adapter)
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
