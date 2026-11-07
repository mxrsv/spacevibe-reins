// Package limits reads the usage limits the CLIs left on disk: Claude Code's usage cache and the status line
// snapshots the collector writes, Codex's rollout logs, and whether Gemini CLI is installed. It makes no
// network request, starts no process and reads no credential (spec, Limits; S-R4, S-R5).
// Ported from Sources/ReinsCore/Limits.swift, LimitsClaudeCache.swift, LimitsClaudeStatusline.swift (the read
// side; the capture side belongs to internal/statusline) and LimitsCodexLogs.swift.
package limits

import (
	"context"
	"os"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/roots"
)

// CLI names a CLI Limits reports on. Gemini CLI appears on this surface only (spec, Limits).
type CLI string

const (
	Claude CLI = "claude"
	Codex  CLI = "codex"
	Gemini CLI = "gemini"
)

// State says what one CLI's files tell about its limits.
type State string

const (
	// Measured: windows from the newest record, taken at Entry.At.
	Measured State = "measured"
	// NotRecorded: installed, but no limit record on disk yet.
	NotRecorded State = "notRecorded"
	// Unreadable: a record exists in a shape the app does not know, or could not be read or looked up. It
	// carries no file content (S-R3).
	Unreadable State = "unreadable"
	// NotMeasurable: the CLI keeps no limit on disk at all (Gemini CLI).
	NotMeasurable State = "notMeasurable"
	NotInstalled  State = "notInstalled"
)

// Source names where a Claude Code reading came from.
type Source string

const (
	ClaudeCache      Source = "claudeCache"
	ClaudeStatusline Source = "claudeStatusline"
)

// Window is one usage-limit window as the CLI last recorded it. Times are seconds since 1970 as numbers
// (fractions allowed), the one place the protocol does not use ISO text.
type Window struct {
	// ID is stable within one CLI: Claude `kind` plus scope, Codex `primary` or `secondary`.
	ID string `json:"id"`
	// Minutes is the length of the window (300 for five hours, 10080 for a week); null when the record does not say.
	Minutes *int `json:"minutes"`
	// Scope is what the window is limited to, such as a model name; null for the whole plan.
	Scope *string `json:"scope"`
	// UsedPercent is the share used, from 0. It can pass 100 when the CLI lets usage run over.
	UsedPercent float64 `json:"usedPercent"`
	ResetsAt    float64 `json:"resetsAt"`
	// Active is false when the CLI marks the window as not applying right now (Claude `is_active`).
	Active bool `json:"active"`
	// Current is ResetsAt > now. After its reset the recorded share no longer describes the window: it reads
	// as unknown, never as 0 (spec, Limits). The window is still returned as recorded.
	Current bool `json:"current"`
}

// Entry is what one CLI's files say about its usage limits.
type Entry struct {
	CLI   CLI   `json:"cli"`
	State State `json:"state"`
	// Plan is the plan the record names (Codex `plan_type`), null when it names none.
	Plan   *string `json:"plan"`
	Source *Source `json:"source"`
	// At is when the record was taken; set only when Measured.
	At *float64 `json:"at"`
	// Windows is empty unless Measured; it is never null on the wire.
	Windows []Window `json:"windows"`
}

// Result is the `limits.read` result: Claude Code, Codex and Gemini CLI, in that order.
type Result struct {
	Limits []Entry `json:"limits"`
}

// Read reads the limits of all three CLIs; now decides each window's Current flag and which status line
// snapshots are not from the future. The only error is ctx's. It blocks on file reads, so call it off the
// UI path.
func Read(ctx context.Context, cfg config.Config, r roots.Roots, now time.Time) (Result, error) {
	nowSeconds := float64(now.UnixNano()) / 1e9
	claude, err := readClaude(ctx, cfg, r, nowSeconds)
	if err != nil {
		return Result{}, err
	}
	codex, err := readCodex(ctx, r)
	if err != nil {
		return Result{}, err
	}
	entries := []Entry{claude, codex, readGemini(r)}
	for i := range entries {
		entries[i] = entries[i].settled(nowSeconds)
	}
	return Result{Limits: entries}, nil
}

// settled marks each window's Current flag and makes Windows a non-nil slice.
func (e Entry) settled(now float64) Entry {
	windows := make([]Window, len(e.Windows))
	for i, w := range e.Windows {
		w.Current = w.ResetsAt > now
		windows[i] = w
	}
	e.Windows = windows
	return e
}

func readGemini(r roots.Roots) Entry {
	return Entry{CLI: Gemini, State: folderState(r.Gemini, NotMeasurable)}
}

// folderState is `found` for a folder, Unreadable when a denied parent hides whether it exists, and
// NotInstalled for anything else (G-fix.15: Swift's fileExists-style check read a denied parent as absent).
func folderState(path string, found State) State {
	switch fsx.PathPresence(path) {
	case fsx.Unknown:
		return Unreadable
	case fsx.Missing:
		return NotInstalled
	}
	if info, err := os.Stat(path); err == nil && info.IsDir() {
		return found
	}
	return NotInstalled
}

func measured(cli CLI, at float64, windows []Window) Entry {
	return Entry{CLI: cli, State: Measured, At: &at, Windows: windows}
}

// dateSeconds is a time stored the way Foundation's Date stores it, seconds since 2001, and read back as
// seconds since 1970. The round trip rounds a value below 2^30 to a coarser step, so Swift's output has it too.
func dateSeconds(unix float64) float64 { return (unix - referenceOffset) + referenceOffset }

// addingSeconds is Date.addingTimeInterval, with the same two roundings as Foundation.
func addingSeconds(unix, seconds float64) float64 {
	return ((unix - referenceOffset) + seconds) + referenceOffset
}

// referenceOffset is the seconds from 1970 to Foundation's reference date, 2001-01-01.
const referenceOffset = 978307200.0
