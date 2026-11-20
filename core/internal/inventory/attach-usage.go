package inventory

import (
	"math"
	"time"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/usage"
)

// Usage cells for the Matrix:
//
//	counted       Runs is how many times it ran (hooks) or how many sessions used it (skills, agents); 0 = never
//	              ran inside the scanned logs. Errors is set for hooks.
//	pending       installed, but no scanned log can have covered it yet (see pendingReason)
//	unmeasurable  the CLI does not log it (Codex hooks); Reason says why
//	missing       not installed in that CLI, which has this kind of item
//	absent        the CLI has no such kind of item (KindSupport absent)

// pendingGrace: a zero-run item that changed inside this window is "pending", not "never ran".
const pendingGraceMs = 24 * 3600 * 1000

// pendingReason is a HEURISTIC, not a fact: the age of an item is unknowable, so "added" is the first time
// SpaceVibe saw its id (first-seen.go) or, without that store, the mtime of its file (SKILL.md, the agent file,
// or the settings file that holds the hook; any edit of that file moves it). An item with zero runs is pending instead of "never ran" when
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
	id    string
	kind  Kind
	name  string
	entry string
	hash  string
	file  string
}

// AttachUsage returns a copy of the snapshot with Cells on every item and hook, and Usage on every hook of a CLI that
// logs hook runs (nil when the scan has not finished or the CLI does not log them). Pure apart from reading file mtimes. Hook
// runs are keyed by event plus command, so the same hook in a global and a project file shares one count: the
// log does not say which file it came from. A nil usage reads like the scanning state.
func AttachUsage(inv Snapshot, in *usage.Input, now time.Time) Snapshot {
	return attachUsage(inv, in, now, nil)
}

// attachUsage is AttachUsage with firstSeen: the first-seen time in ms by item id, from the store of
// Service.Rows. An id it holds is "added" at that time; any other id falls back to the file's mtime.
func attachUsage(inv Snapshot, in *usage.Input, now time.Time, firstSeen map[string]float64) Snapshot {
	nowMs := float64(now.UnixNano()) / 1e6
	groups := map[string]map[clis.ID]matrixRow{}
	add := func(key string, cli clis.ID, row matrixRow) {
		if groups[key] == nil {
			groups[key] = map[clis.ID]matrixRow{}
		}
		groups[key][cli] = row
	}
	for _, item := range inv.Items {
		add(item.Key(), item.CLI, matrixRow{id: item.ID, kind: item.Kind, name: item.Name, entry: item.Entry, file: item.File})
	}
	for _, hook := range inv.Hooks {
		add(hook.Key(), hook.CLI, matrixRow{id: hook.ID, kind: KindHook, hash: hook.Hash, file: hook.File})
	}
	type mtime struct {
		ms *float64
	}
	mtimes := map[string]mtime{}
	addedAt := func(id, file string) *float64 {
		if ms, ok := firstSeen[id]; ok {
			return &ms
		}
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
	cellFor := func(row *matrixRow, kind Kind, cli clis.Bound[inventoryAdapter]) Cell {
		support := cli.Adapter.kinds().Of(kind)
		if row == nil {
			if support.Support == SupportAbsent {
				return Absent()
			}
			return Missing()
		}
		if support.Runs == RunsNotLogged {
			return Unmeasurable(support.NotLoggedReason)
		}
		if totals == nil {
			return Pending(ScanNotFinished)
		}
		perCLI, err := totals.For(cli.ID)
		if err != nil { // a CLI whose logs are not scanned: its runs cannot be counted, never another CLI's
			return Unmeasurable(NotScannedReason)
		}
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
			if row.kind == KindSkill && row.entry != "" {
				// Codex logs a skill under its folder name, which can differ from the frontmatter name. One
				// session can match both names, so take the larger count instead of adding them; the last day is
				// the later of the two.
				byEntry := names[hashes.Bare(row.entry)]
				last := n.Last
				if byEntry.Last != nil && (last == nil || *byEntry.Last > *last) {
					last = byEntry.Last
				}
				if byEntry.Sessions > n.Sessions {
					n = byEntry
				}
				n.Last = last
			}
			runs, last = n.Sessions, n.Last
		}
		if runs == 0 {
			var window *usage.LogWindow
			if windows != nil {
				if w, err := windows.For(cli.ID); err == nil {
					window = &w
				}
			}
			if reason := pendingReason(addedAt(row.id, row.file), window, nowMs); reason != "" {
				return Pending(reason)
			}
		}
		return Counted(runs, last, errors)
	}
	// One cell per CLI with the inventory concept, in wire order, whichever CLI holds the row.
	cellsFor := func(key string, kind Kind) Cells {
		group := groups[key]
		out := Cells{}
		for _, cli := range adapters.InOrder() {
			var row *matrixRow
			if r, ok := group[cli.ID]; ok {
				row = &r
			}
			cell := cellFor(row, kind, cli)
			cell.CLI = cli.ID
			out = append(out, cell)
		}
		return out
	}

	out := inv
	out.Items = make([]Item, len(inv.Items))
	for i, item := range inv.Items {
		item.Cells = cellsFor(item.Key(), item.Kind)
		out.Items[i] = item
	}
	out.Hooks = make([]Hook, len(inv.Hooks))
	for i, hook := range inv.Hooks {
		hook.Cells = cellsFor(hook.Key(), KindHook)
		hook.Usage = nil
		if perCLI, ok := loggedHookTotals(totals, hook.CLI); ok {
			u := perCLI.Hook[hook.Hash]
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

// loggedHookTotals are the usage totals of cli when its logs record hook runs and a scan has finished.
func loggedHookTotals(totals *usage.Totals, cli clis.ID) (usage.CLITotals, bool) {
	if totals == nil {
		return usage.CLITotals{}, false
	}
	if reason, err := UnloggedHooks(cli); err != nil || reason != "" {
		return usage.CLITotals{}, false
	}
	perCLI, err := totals.For(cli)
	return perCLI, err == nil
}
