// Package inventory reads what is installed for Claude Code and Codex (skills, subagents and hooks, plugin
// owned items, the .claude folders of discovered projects), attaches the usage cells the Matrix shows, and
// builds the loadout.rows result. It never executes anything. Settings are read only for hooks, plugin flags
// and skill overrides: no other value, in particular env, is kept or returned (S-R3).
//
// Ported from Sources/ReinsCore/Inventory*.swift (InventoryReader, InventoryTypes, InventoryFileIO,
// InventoryProjects, InventoryHash, InventoryScriptPaths, InventoryUsageAttach, InventoryFilterCounts) and
// Frontmatter.swift, plus the pure helpers of Sources/SpaceVibe/Loadout/LoadoutRows.swift (LoadoutData.build,
// the per-row filter flags). The usage side lives in internal/usage, which this package imports.
package inventory

import (
	"encoding/json"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/usage"
)

// CLI is claude or codex.
type CLI = usage.CLI

// The CLIs.
const (
	Claude = usage.Claude
	Codex  = usage.Codex
)

// Kind is the wire value of kind: skill, agent or hook.
type Kind string

// The kinds.
const (
	KindSkill Kind = "skill"
	KindAgent Kind = "agent"
	KindHook  Kind = "hook"
)

// Scope is global (user level) or project.
type Scope string

// The scopes.
const (
	ScopeGlobal  Scope = "global"
	ScopeProject Scope = "project"
)

const (
	// MaxProjects: at most this many project folders are discovered, newest first.
	MaxProjects = 300
	// CodexHooksReason is why a Codex hook cell is unmeasurable.
	CodexHooksReason = "Codex does not log hook runs"
	// ScanNotFinished is the pending reason before the first scan has finished.
	ScanNotFinished = "Usage scan has not finished"
)

// Events are the hook events each CLI documents. Claude's list comes from its docs; Codex's from
// observation only.
func Events() map[string][]string {
	return map[string][]string{
		"claude": {"SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Notification", "SubagentStart", "SubagentStop", "Elicitation", "ElicitationResult", "TeammateIdle", "PreCompact", "PostCompact", "Stop", "StopFailure", "SessionEnd"},
		"codex":  {"SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "SubagentStart", "SubagentStop", "Interrupt", "Stop", "SessionEnd"},
	}
}

// Cell states.
const (
	StateCounted      = "counted"
	StatePending      = "pending"
	StateUnmeasurable = "unmeasurable"
	StateMissing      = "missing"
)

// Cell is the usage cell of one CLI for one row: counted, pending, unmeasurable or missing.
//
//   - counted: Runs is hook runs, or sessions that used the skill or agent; 0 means it never ran inside the
//     scanned logs. Errors is set for hooks only. Last is null when unknown.
//   - pending: installed, but no scanned log can have covered it yet; Reason says why.
//   - unmeasurable: the CLI does not log it (Codex hooks); Reason says why.
//   - missing: not installed in that CLI.
type Cell struct {
	State  string
	Runs   int
	Last   *string
	Errors *int
	Reason string
}

// IsMissing reports whether the item is not installed in that CLI.
func (c Cell) IsMissing() bool { return c.State == StateMissing }

// MarshalJSON writes the shape of UsageCellState.encode: counted has state, runs, errors (when set) and
// last (null when unknown); pending and unmeasurable have state and reason; missing has only state.
func (c Cell) MarshalJSON() ([]byte, error) {
	switch c.State {
	case StateCounted:
		return json.Marshal(struct {
			State  string  `json:"state"`
			Runs   int     `json:"runs"`
			Errors *int    `json:"errors,omitempty"`
			Last   *string `json:"last"`
		}{c.State, c.Runs, c.Errors, c.Last})
	case StatePending, StateUnmeasurable:
		return json.Marshal(struct {
			State  string `json:"state"`
			Reason string `json:"reason"`
		}{c.State, c.Reason})
	default:
		return json.Marshal(struct {
			State string `json:"state"`
		}{StateMissing})
	}
}

// UnmarshalJSON reads the same shapes back; an unknown state is an error.
func (c *Cell) UnmarshalJSON(data []byte) error {
	var raw struct {
		State  string  `json:"state"`
		Runs   *int    `json:"runs"`
		Errors *int    `json:"errors"`
		Last   *string `json:"last"`
		Reason *string `json:"reason"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	switch raw.State {
	case StateCounted:
		if raw.Runs == nil {
			return errBadCell
		}
		*c = Cell{State: StateCounted, Runs: *raw.Runs, Last: raw.Last, Errors: raw.Errors}
	case StatePending, StateUnmeasurable:
		if raw.Reason == nil {
			return errBadCell
		}
		*c = Cell{State: raw.State, Reason: *raw.Reason}
	case StateMissing:
		*c = Cell{State: StateMissing}
	default:
		return errBadCell
	}
	return nil
}

// Counted is a counted cell.
func Counted(runs int, last *string, errors *int) Cell {
	return Cell{State: StateCounted, Runs: runs, Last: last, Errors: errors}
}

// Pending is a pending cell.
func Pending(reason string) Cell { return Cell{State: StatePending, Reason: reason} }

// Unmeasurable is an unmeasurable cell.
func Unmeasurable(reason string) Cell { return Cell{State: StateUnmeasurable, Reason: reason} }

// Missing is a missing cell.
func Missing() Cell { return Cell{State: StateMissing} }

// Cells holds one cell per CLI.
type Cells struct {
	Claude Cell `json:"claude"`
	Codex  Cell `json:"codex"`
}

// For returns the cell of one CLI.
func (c Cells) For(cli CLI) Cell {
	if cli == Claude {
		return c.Claude
	}
	return c.Codex
}

// Item is a skill or a subagent. The JSON names are the Node output's.
type Item struct {
	ID   string `json:"id"`
	CLI  CLI    `json:"cli"`
	Kind Kind   `json:"kind"`
	Name string `json:"name"`
	// Entry is the folder name (skill) or file name (agent).
	Entry       string `json:"entry"`
	Description string `json:"description"`
	// Owner is "user", "link" (a symlink), or the plugin name.
	Owner string `json:"owner"`
	Path  string `json:"path"`
	File  string `json:"file"`
	// Removable: the user can remove it, a user-level item, not one owned by a plugin and not inside a project.
	Removable bool  `json:"removable"`
	Scope     Scope `json:"scope"`
	// Project is the absolute path of the owning project, or nil for user-level config.
	Project *string `json:"project"`
	// InOther: the same row exists in the other CLI.
	InOther bool `json:"inOther"`
	// HasSkillOverride is true for Claude global skills: the override member is then written, null when
	// settings hold no value (SkillOverride nil). Other items leave the member out.
	HasSkillOverride bool
	SkillOverride    *string
	// Cells is set by AttachUsage.
	Cells *Cells `json:"cells,omitempty"`
}

// Key is the matrix row this item belongs to: the same name (or hook) in the same project, whichever CLI
// holds it.
func (i Item) Key() string {
	return string(i.Kind) + ":" + deref(i.Project) + ":" + hashes.Bare(i.Name)
}

// HookUsage is what the logs say about one hook (Claude only). Runs counts every record of the hook;
// AvgMs is over timed runs.
type HookUsage struct {
	Runs    int     `json:"runs"`
	AvgMs   *int    `json:"avgMs"`
	TotalMs float64 `json:"totalMs"`
	Errors  int     `json:"errors"`
	Last    *string `json:"last"`
}

// Hook is one hook command in a settings file (Claude settings.json, Codex hooks.json, a plugin's hooks.json).
type Hook struct {
	ID      string   `json:"id"`
	CLI     CLI      `json:"cli"`
	Event   string   `json:"event"`
	Matcher *string  `json:"matcher"`
	Command string   `json:"command"`
	Timeout *float64 `json:"timeout"`
	Async   bool     `json:"async"`
	// Owner is "user" or the plugin name.
	Owner     string `json:"owner"`
	Removable bool   `json:"removable"`
	// Dead: the command names script paths and none of them exists.
	Dead bool `json:"dead"`
	// Paths are the absolute script paths the command names. Never nil.
	Paths []string `json:"paths"`
	// Hash is the first 12 hex of sha1(event|command): the identity the logs use.
	Hash    string  `json:"hash"`
	File    string  `json:"file"`
	Scope   Scope   `json:"scope"`
	Project *string `json:"project"`
	Cells   *Cells  `json:"cells,omitempty"`
	// Usage is nil when unknown (scan not finished) or not logged (Codex); always written, as null then.
	Usage *HookUsage `json:"usage"`
}

// Key is the matrix row of the hook.
func (h Hook) Key() string { return "hook:" + deref(h.Project) + ":" + h.Hash }

// Snapshot is everything installed, read from disk. Problems are plain sentences for the UI.
type Snapshot struct {
	Items    []Item   `json:"items"`
	Hooks    []Hook   `json:"hooks"`
	Problems []string `json:"problems"`
	// Events are the hook events each CLI documents.
	Events map[string][]string `json:"events"`
	// Roots is the config root of each CLI, keyed claude and codex.
	Roots map[string]string `json:"roots"`
}

// FilterCounts are the counts for the filter chips, deduplicated by row key.
type FilterCounts struct {
	All  int      `json:"all"`
	Only OnlyCLIs `json:"only"`
	// NeverRan: ran in no CLI that logs it, and at least one CLI counted it. A dead hook is counted only
	// under Dead.
	NeverRan int `json:"neverRan"`
	Dead     int `json:"dead"`
}

// OnlyCLIs counts the rows present in one CLI only.
type OnlyCLIs struct {
	Claude int `json:"claude"`
	Codex  int `json:"codex"`
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func strPtr(s string) *string { return &s }
