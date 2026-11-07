// Package activity is the Activity tab's data: the running sessions of both CLIs, failed commands and file history.
//
// Ported from Sources/ReinsCore/Activity.swift (ActivityEngine, readActivity), ActivityFold.swift,
// ActivityGroups.swift, ActivityStop.swift and SessionTitles.swift (ActivityText is internal/textjs). The Swift code
// is the spec, quirks included; the patterns that ran on ICU are in icu-patterns.go.
//
// It is read-only on logs and never runs a recorded command or hook (R4). All process access goes through
// proc.Adapter. The engine keeps the read offsets and folded state of every log between calls, so a repeated Read
// reads only the bytes appended since; a compressed rollout is folded again only when its file changes.
//
// Result types carry the json tags of docs/internals/core-protocol.md. Every slice is non-nil so it encodes as [].
package activity

import (
	"math"

	"spacevibe.dev/core/internal/pricing"
)

// CLI is one of the two command line tools whose logs are read.
type CLI string

// The CLIs, ordered as their raw values sort ("claude" before "codex").
const (
	CLIClaude CLI = "claude"
	CLICodex  CLI = "codex"
)

// SessionState is what a session is doing now.
type SessionState string

// The session states.
const (
	StateRunning      SessionState = "running"
	StateWaiting      SessionState = "waiting"
	StateIdle         SessionState = "idle"
	StateEnded        SessionState = "ended"
	StateUnmeasurable SessionState = "unmeasurable"
)

// Reason is a code for something that cannot be known. The wording is Activity's own.
type Reason string

// The reasons a state cannot be known.
const (
	ReasonCodexNoRollout      Reason = "codex-no-rollout"
	ReasonCodexToolSilent     Reason = "codex-tool-silent"
	ReasonClaudePromptVsBusy  Reason = "claude-prompt-vs-busy"
	ReasonClaudeUnknownStatus Reason = "claude-unknown-status"
	ReasonCodexHookRuns       Reason = "codex-hook-runs"
)

// Text is the sentence shown for the reason.
func (r Reason) Text() string {
	switch r {
	case ReasonCodexNoRollout:
		return "Codex writes no log until the first prompt is sent, so this session cannot be read yet."
	case ReasonCodexToolSilent:
		return "Codex logs nothing while a tool runs and does not record approval waits, so a long command and a wait for approval look the same."
	case ReasonClaudePromptVsBusy:
		return "Claude Code does not record permission prompts, so a long tool run and a wait for approval look the same."
	case ReasonClaudeUnknownStatus:
		return "The Claude Code status file reports a status this app does not know."
	case ReasonCodexHookRuns:
		return "Codex does not log hook runs, so failed hooks are not shown for Codex."
	}
	return ""
}

// Tool is the tool call a session has open.
type Tool struct {
	Name   string `json:"name"`
	Target string `json:"target"`
}

// Cost is an API-equivalent estimate, not what a subscription charges (Estimated is always true).
type Cost struct {
	USD       float64 `json:"usd"`
	Estimated bool    `json:"estimated"`
}

// Session is one live (or recently ended) CLI session.
type Session struct {
	CLI CLI `json:"cli"`
	// ID is Claude: the session id. Codex: the thread id, or `pid:<n>:<start-ms>` before the first prompt.
	// An unknown process start uses `pid:<n>:unknown` and cannot authorize Stop.
	ID      string       `json:"id"`
	Title   string       `json:"title"`
	Project *string      `json:"project"`
	Pid     int          `json:"pid"`
	State   SessionState `json:"state"`
	// StateReason is the sentence that explains State.
	StateReason string `json:"stateReason"`
	// ReasonCode is set when State is unmeasurable.
	ReasonCode  *Reason `json:"reasonCode"`
	CurrentTool *Tool   `json:"currentTool"`
	// AgeMs is milliseconds since the session started.
	AgeMs *float64 `json:"ageMs"`
	// LastWriteAgoMs is milliseconds since the transcript (or a subagent transcript) was last written. This is the
	// age to show: Claude's statusUpdatedAt goes stale.
	LastWriteAgoMs *float64 `json:"lastWriteAgoMs"`
	Cost           *Cost    `json:"cost"`
	CostNote       *string  `json:"costNote"`
}

// Limit is something that cannot be measured, listed even when no session is live.
type Limit struct {
	CLI  CLI    `json:"cli"`
	Code Reason `json:"code"`
	Text string `json:"text"`
}

// Stats counts the logs of one read.
type Stats struct {
	// Logs folded in this read.
	Logs int `json:"logs"`
	// Truncated logs were read from their tail only, so older records are missing and their cost is not estimated.
	Truncated int `json:"truncated"`
}

// FailureKind tells a failed command from a failing hook.
type FailureKind string

// The failure kinds.
const (
	KindCommand FailureKind = "command"
	KindHook    FailureKind = "hook"
)

// HookRef names the hook behind a hook failure.
type HookRef struct {
	Hash  string `json:"hash"`
	Event string `json:"event"`
}

// Failure is a repeated failed command (or failing hook), grouped across sessions.
type Failure struct {
	Kind FailureKind `json:"kind"`
	CLI  CLI         `json:"cli"`
	// Key is, for a command, the sha of the normalized command; for a hook, the inventory hash sha(event|command).
	Key string `json:"key"`
	// Title is the command, one form for every failure (a long one is cut at 120 characters).
	Title    string   `json:"title"`
	Count    int      `json:"count"`
	Exit     *int     `json:"exit"`
	Reason   string   `json:"reason"`
	Projects []string `json:"projects"`
	Sessions int      `json:"sessions"`
	First    *string  `json:"first"`
	Last     *string  `json:"last"`
	// LaterPass is the first passing run of the same command after the last failure. A timestamp only: it does not
	// say the failure was fixed.
	LaterPass *string  `json:"laterPass"`
	Hook      *HookRef `json:"hook"`
}

// FileRow is the edits of one file across sessions, with the shortest path suffix that tells it from the others.
type FileRow struct {
	Path     string   `json:"path"`
	Label    string   `json:"label"`
	Edits    int      `json:"edits"`
	Sessions int      `json:"sessions"`
	Last     *string  `json:"last"`
	CLIs     []CLI    `json:"clis"`
	Projects []string `json:"projects"`
}

// Report is everything the Activity tab shows.
type Report struct {
	Sessions     []Session `json:"sessions"`
	Failures     []Failure `json:"failures"`
	Files        []FileRow `json:"files"`
	Unmeasurable []Limit   `json:"unmeasurable"`
	Stats        Stats     `json:"stats"`
}

// Options are the limits of one read. Use DefaultOptions and change fields.
type Options struct {
	HistoryDays      int
	MaxHistoryFiles  int
	HistoryTailBytes int64
	LiveTailBytes    int64
	FailureLimit     int
	FileLimit        int
	// ToolQuietMs: an open tool call with no log write for this long is ambiguous (running, or waiting for approval).
	ToolQuietMs float64
	// EndedKeepMs: a dead Claude session is listed as "ended" for this long.
	EndedKeepMs float64
}

// DefaultOptions are the limits the app reads with.
func DefaultOptions() Options {
	return Options{
		HistoryDays:      14,
		MaxHistoryFiles:  200,
		HistoryTailBytes: 4 * 1024 * 1024,
		LiveTailBytes:    64 * 1024 * 1024,
		FailureLimit:     200,
		FileLimit:        300,
		ToolQuietMs:      30_000,
		EndedKeepMs:      15 * 60_000,
	}
}

// limitCodes are the unmeasurable limits listed in every report, in this order.
var limitCodes = []struct {
	cli  CLI
	code Reason
}{
	{CLIClaude, ReasonClaudePromptVsBusy}, {CLICodex, ReasonCodexToolSilent}, {CLICodex, ReasonCodexNoRollout}, {CLICodex, ReasonCodexHookRuns},
}

// usage is the token counts of one model, as the log folding sums them.
type usage = pricing.Usage

func strPtr(s string) *string { return &s }

var inf = math.Inf(1)
