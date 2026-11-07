package inventory

import (
	"math"
	"time"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/usage"
)

// Usage cells for the Matrix:
//
//	counted       Runs is how many times it ran (hooks) or how many sessions used it (skills, agents); 0 = never
//	              ran inside the scanned logs. Errors is set for hooks.
//	pending       installed, but no scanned log can have covered it yet (see pendingReason)
//	unmeasurable  the CLI does not log it (Codex hooks); Reason says why
//	missing       not installed in that CLI

// pendingGrace: a zero-run item that changed inside this window is "pending", not "never ran".
const pendingGraceMs = 24 * 3600 * 1000

// pendingReason is a HEURISTIC, not a fact: the age of an item is unknowable, so the mtime of its file stands
// in for "installed at" (SKILL.md, the agent file, or the settings file that holds the hook; any edit of that
// file moves it). An item with zero runs is pending instead of "never ran" when
//  1. its CLI has no scanned logs at all, or
//  2. it changed within the last 24 hours, or
//  3. it changed after the newest scanned log, so no session could have used it yet.
func pendingReason(addedMs *float64, window *usage.LogWindow, nowMs float64) string {
	if window != nil && window.Files == 0 {
		return "No logs scanned for this CLI yet"
	}
	if addedMs != nil && nowMs-*addedMs < pendingGraceMs {
		return "Added in the last 24 hours"
	}
	if addedMs != nil && window != nil && window.Newest != nil && *addedMs > float64(*window.Newest) {
		return "Added after the newest log"
	}
	return ""
}

type matrixRow struct {
	kind Kind
	name string
	hash string
	file string
}

// AttachUsage returns a copy of the snapshot with Cells on every item and hook, and Usage on every Claude hook
// (nil when the scan has not finished or the CLI does not log it). Pure apart from reading file mtimes. Hook
// runs are keyed by event plus command, so the same hook in a global and a project file shares one count: the
// log does not say which file it came from. A nil usage reads like the scanning state.
func AttachUsage(inv Snapshot, in *usage.Input, now time.Time) Snapshot {
	nowMs := float64(now.UnixNano()) / 1e6
	groups := map[string]map[CLI]matrixRow{}
	add := func(key string, cli CLI, row matrixRow) {
		if groups[key] == nil {
			groups[key] = map[CLI]matrixRow{}
		}
		groups[key][cli] = row
	}
	for _, item := range inv.Items {
		add(item.Key(), item.CLI, matrixRow{kind: item.Kind, name: item.Name, file: item.File})
	}
	for _, hook := range inv.Hooks {
		add(hook.Key(), hook.CLI, matrixRow{kind: KindHook, hash: hook.Hash, file: hook.File})
	}
	type mtime struct {
		ms *float64
	}
	mtimes := map[string]mtime{}
	addedAt := func(file string) *float64 {
		if known, ok := mtimes[file]; ok {
			return known.ms
		}
		var ms *float64
		if v, ok := modifiedMs(file); ok {
			ms = &v
		}
		mtimes[file] = mtime{ms}
		return ms
	}
	var totals *usage.Totals
	var windows *usage.Windows
	if in != nil {
		totals, windows = in.Totals, in.Windows
	}
	cellFor := func(row *matrixRow, cli CLI) Cell {
		if row == nil {
			return Missing()
		}
		if row.kind == KindHook && cli == Codex {
			return Unmeasurable(CodexHooksReason)
		}
		if totals == nil {
			return Pending(ScanNotFinished)
		}
		perCLI := totals.For(cli)
		var runs int
		var last *string
		var errors *int
		if row.kind == KindHook {
			h := perCLI.Hook[row.hash]
			runs, last = h.Runs, h.Last
			e := h.Errors
			errors = &e
		} else {
			names := perCLI.Skill
			if row.kind == KindAgent {
				names = perCLI.Agent
			}
			n := names[hashes.Bare(row.name)]
			runs, last = n.Sessions, n.Last
		}
		if runs == 0 {
			var window *usage.LogWindow
			if windows != nil {
				w := windows.For(cli)
				window = &w
			}
			if reason := pendingReason(addedAt(row.file), window, nowMs); reason != "" {
				return Pending(reason)
			}
		}
		return Counted(runs, last, errors)
	}
	cellsFor := func(key string) *Cells {
		group := groups[key]
		get := func(cli CLI) *matrixRow {
			if row, ok := group[cli]; ok {
				return &row
			}
			return nil
		}
		return &Cells{Claude: cellFor(get(Claude), Claude), Codex: cellFor(get(Codex), Codex)}
	}

	out := inv
	out.Items = make([]Item, len(inv.Items))
	for i, item := range inv.Items {
		item.Cells = cellsFor(item.Key())
		out.Items[i] = item
	}
	out.Hooks = make([]Hook, len(inv.Hooks))
	for i, hook := range inv.Hooks {
		hook.Cells = cellsFor(hook.Key())
		hook.Usage = nil
		if hook.CLI == Claude && totals != nil {
			u := totals.Claude.Hook[hook.Hash]
			var avg *int
			if u.Timed > 0 {
				v := int(math.Round(u.Ms / float64(u.Timed)))
				avg = &v
			}
			hook.Usage = &HookUsage{Runs: u.Runs, AvgMs: avg, TotalMs: u.Ms, Errors: u.Errors, Last: u.Last}
		}
		out.Hooks[i] = hook
	}
	return out
}
