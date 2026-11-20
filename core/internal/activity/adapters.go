package activity

import (
	"context"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// logFolder reads one CLI's session log lines into a logState.
type logFolder interface {
	// fold folds one log line into st.
	fold(st *logState, line []byte)
	// edits are the file edits a folded log records.
	edits(st *logState) []editEvent
}

// sessionSource finds one CLI's running sessions.
type sessionSource interface {
	// listLogs indexes the CLI's logs for one Read.
	listLogs(cli roots.CLIRoots) cliRead
	// limits are the reasons that always leave some state of this CLI unmeasurable; every report lists them.
	limits() []Reason
	// approvalLimit is the one of limits that says a wait for approval cannot be told from a busy tool run, the
	// reason the CLI's state function gives such a session; "" when the CLI has none.
	approvalLimit() Reason
}

// cliRead is one CLI's part of one Read: its logs, the live sessions found from them and from the process table,
// and their rows.
type cliRead interface {
	// files are the CLI's logs.
	files() []logFile
	// findLive looks up the live sessions; it runs once per Read, after every CLI listed its logs.
	findLive(ctx context.Context, adapter proc.Adapter)
	// livePaths are the logs of live sessions, folded in full.
	livePaths() []string
	// sessions are the rows, built once every log was folded.
	sessions(ctx context.Context, rc *readContext) []Session
	// extraLimits are limits that hold for this Read only (a failed process listing).
	extraLimits() []Limit
}

// stopper finds the process of one live session for Stop.
type stopper interface {
	// livePid decides the process from the system now, never from the caller (R6).
	livePid(ctx context.Context, cli roots.CLIRoots, id string, adapter proc.Adapter) lookup
}

// activityAdapter is everything one CLI contributes to Activity.
type activityAdapter interface {
	logFolder
	sessionSource
	stopper
}

// adapters is the Activity adapter of every CLI with the activity concept. A CLI without one has no sessions to
// list or stop: its logs are never folded as another CLI's.
var adapters = clis.NewAdapters(clis.Activity, map[clis.ID]activityAdapter{
	clis.Claude: claudeActivity{},
	clis.Codex:  codexActivity{},
})

// folderOf is the log folder of cli, or an error wrapping clis.ErrUnknownCLI or clis.ErrConceptAbsent.
func folderOf(cli clis.ID) (logFolder, error) { return adapters.For(cli) }

// editsOf is the edits of one folded log, read by its CLI's folder.
func editsOf(st *logState) ([]editEvent, error) {
	folder, err := folderOf(st.cli)
	if err != nil {
		return nil, err
	}
	return folder.edits(st), nil
}

// fixedLimits are the unmeasurable limits listed in every report: each CLI's own, in wire order.
func fixedLimits() []Limit {
	var out []Limit
	for _, a := range adapters.InOrder() {
		for _, code := range a.Adapter.limits() {
			out = append(out, Limit{CLI: a.ID, Code: code, Text: code.Text()})
		}
	}
	return out
}

// ApprovalLimit is the limit code a session of cli carries when a wait for approval cannot be told from a busy tool
// run: "" when it has none, or an error wrapping clis.ErrUnknownCLI or clis.ErrConceptAbsent.
func ApprovalLimit(cli clis.ID) (Reason, error) {
	a, err := adapters.For(cli)
	if err != nil {
		return "", err
	}
	return a.approvalLimit(), nil
}
