// Package inventory reads what is installed for each CLI with the inventory concept (skills, subagents and hooks,
// plugin owned items, the .claude folders of discovered projects; per-CLI facts in claude.go and codex.go behind
// adapters.go), attaches the usage cells the Matrix shows, and
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

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/hashes"
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
	// ScanNotFinished is the pending reason before the first scan has finished.
	ScanNotFinished = "Usage scan has not finished"
	// NotScannedReason is the unmeasurable reason of a CLI whose logs the usage scan does not read (no usage
	// concept). No CLI on the wire today is in that state.
	NotScannedReason = "SpaceVibe does not read this CLI's logs"
)

// Cell states.
const (
	StateCounted      = "counted"
	StatePending      = "pending"
	StateUnmeasurable = "unmeasurable"
	StateMissing      = "missing"
	StateAbsent       = "absent"
)

// Cell is the usage cell of one CLI for one row: counted, pending, unmeasurable, missing or absent.
//
//   - counted: Runs is hook runs, or sessions that used the skill or agent; 0 means it never ran inside the
//     scanned logs. Errors is set for hooks only. Last is null when unknown.
//   - pending: installed, but no scanned log can have covered it yet; Reason says why.
//   - unmeasurable: the CLI does not log it (Codex hooks); Reason says why.
//   - missing: the CLI has this kind of item, but this one is not installed in it.
//   - absent: the CLI has no such kind of item at all (KindSupport absent). Never an add target, never 0.
type Cell struct {
	// CLI is the CLI the cell belongs to. The constructors leave it empty; the cells of a row set it.
	CLI    clis.ID
	State  string
	Runs   int
	Last   *string
	Errors *int
	Reason string
}

// CLIID is the CLI the cell belongs to.
func (c Cell) CLIID() clis.ID { return c.CLI }

// IsMissing reports whether the item is not installed in that CLI.
func (c Cell) IsMissing() bool { return c.State == StateMissing }

// IsPresent reports whether the item is installed in that CLI: neither missing nor absent.
func (c Cell) IsPresent() bool { return c.State != StateMissing && c.State != StateAbsent }

// MarshalJSON writes cli, then the shape of UsageCellState.encode: counted has state, runs, errors (when set) and
// last (null when unknown); pending and unmeasurable have state and reason; missing and absent have only state.
func (c Cell) MarshalJSON() ([]byte, error) {
	switch c.State {
	case StateCounted:
		return json.Marshal(struct {
			CLI    clis.ID `json:"cli"`
			State  string  `json:"state"`
			Runs   int     `json:"runs"`
			Errors *int    `json:"errors,omitempty"`
			Last   *string `json:"last"`
		}{c.CLI, c.State, c.Runs, c.Errors, c.Last})
	case StatePending, StateUnmeasurable:
		return json.Marshal(struct {
			CLI    clis.ID `json:"cli"`
			State  string  `json:"state"`
			Reason string  `json:"reason"`
		}{c.CLI, c.State, c.Reason})
	case StateAbsent:
		return json.Marshal(struct {
			CLI   clis.ID `json:"cli"`
			State string  `json:"state"`
		}{c.CLI, StateAbsent})
	default:
		return json.Marshal(struct {
			CLI   clis.ID `json:"cli"`
			State string  `json:"state"`
		}{c.CLI, StateMissing})
	}
}

// UnmarshalJSON reads the same shapes back; an unknown state is an error.
func (c *Cell) UnmarshalJSON(data []byte) error {
	var raw struct {
		CLI    clis.ID `json:"cli"`
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
	case StateMissing, StateAbsent:
		*c = Cell{State: raw.State}
	default:
		return errBadCell
	}
	c.CLI = raw.CLI
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

// Absent is the cell of a CLI that has no such kind of item.
func Absent() Cell { return Cell{State: StateAbsent} }

// Cells holds one cell per CLI with the inventory concept, in wire order.
type Cells []Cell

// For is the cell of one CLI; false when the row has none for it. It never answers with another CLI's cell.
func (c Cells) For(cli clis.ID) (Cell, bool) { return clis.Find(c, cli) }

// Item is a skill or a subagent. The JSON names are the Node output's.
type Item struct {
	ID  string  `json:"id"`
	CLI clis.ID `json:"cli"`
	// ReadBy are the CLIs that read this item's file, in wire order (spec MC-R7). Today every item is read by its own
	// CLI alone; a folder several CLIs read will list each of them. CLI stays the folder's owner, which the id names.
	ReadBy []clis.ID `json:"readBy"`
	Kind   Kind      `json:"kind"`
	Name   string    `json:"name"`
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
	// HasSkillOverride is true for Claude global skills: the override member is then written, null when
	// settings hold no value (SkillOverride nil). Other items leave the member out.
	HasSkillOverride bool
	SkillOverride    *string
	// Cells is set by AttachUsage. Whether the row exists in another CLI is what its cells say.
	Cells Cells `json:"cells,omitempty"`
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
	CLI     clis.ID  `json:"cli"`
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
	Cells   Cells   `json:"cells,omitempty"`
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
	// Events are the hook events each CLI with the inventory concept documents, in wire order.
	Events []CLIEvents `json:"events"`
	// Roots is the config root of each CLI with the inventory concept, in wire order.
	Roots []CLIRoot `json:"roots"`
}

// CLIEvents are the hook events one CLI documents.
type CLIEvents struct {
	CLI    clis.ID  `json:"cli"`
	Events []string `json:"events"`
}

// CLIID is the CLI the events belong to.
func (e CLIEvents) CLIID() clis.ID { return e.CLI }

// CLIRoot is one CLI's config root folder.
type CLIRoot struct {
	CLI  clis.ID `json:"cli"`
	Root string  `json:"root"`
}

// CLIID is the CLI the root belongs to.
func (r CLIRoot) CLIID() clis.ID { return r.CLI }

// FilterCounts are the counts for the filter chips, deduplicated by row key.
type FilterCounts struct {
	All int `json:"all"`
	// Only counts, per CLI with the inventory concept in wire order, the rows present in that CLI alone.
	Only OnlyCLIs `json:"only"`
	// NeverRan: ran in no CLI that logs it, and at least one CLI counted it. A dead hook is counted only
	// under Dead.
	NeverRan int `json:"neverRan"`
	Dead     int `json:"dead"`
}

// OnlyCount is the number of rows present in one CLI alone.
type OnlyCount struct {
	CLI   clis.ID `json:"cli"`
	Count int     `json:"count"`
}

// CLIID is the CLI the count belongs to.
func (o OnlyCount) CLIID() clis.ID { return o.CLI }

// OnlyCLIs holds one OnlyCount per CLI with the inventory concept, in wire order.
type OnlyCLIs []OnlyCount

// total is the number of rows present in exactly one CLI, whichever it is.
func (o OnlyCLIs) total() int {
	n := 0
	for _, c := range o {
		n += c.Count
	}
	return n
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func strPtr(s string) *string { return &s }
