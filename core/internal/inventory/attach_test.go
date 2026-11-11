package inventory

import (
	"reflect"
	"testing"
	"time"

	"spacevibe.dev/core/internal/usage"
)

// cellsFixture is the home of the Swift InventoryTests "usage cells" suite.
type cellsFixture struct {
	inventory Snapshot
	now       time.Time
	newestLog int64
}

func newCellsFixture(t *testing.T) cellsFixture {
	t.Helper()
	h := newTempHome(t)
	skill := func(cli, name, iso string) {
		h.setModified(h.write("."+cli+"/skills/"+name+"/SKILL.md", skillFile(name)), iso)
	}
	skill("claude", "both", "2026-09-20T00:00:00Z")
	skill("codex", "both", "2026-09-20T00:00:00Z")
	skill("claude", "only-claude", "2026-09-20T00:00:00Z")
	skill("claude", "after-log", "2026-10-30T00:00:00Z")
	skill("claude", "fresh", "2026-11-02T08:00:00Z")
	h.setModified(h.write(".claude/settings.json", `{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo ran"}, {"type": "command", "command": "sh '`+h.root+`/gone/dead.sh'"}]}]}}`), "2026-09-20T00:00:00Z")
	h.setModified(h.write(".codex/hooks.json", `{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo codex-only"}]}]}}`), "2026-09-20T00:00:00Z")
	return cellsFixture{
		inventory: Read(h.roots()),
		now:       mustTime(t, "2026-11-02T12:00:00Z"),
		newestLog: mustTime(t, "2026-10-29T00:00:00Z").UnixMilli(),
	}
}

func (f cellsFixture) totals() *usage.Totals {
	empty := func() usage.CLITotals {
		return usage.CLITotals{Skill: map[string]usage.NameUsage{}, Agent: map[string]usage.NameUsage{}, Hook: map[string]usage.HookTotals{}}
	}
	claude := empty()
	claude.Skill["both"] = usage.NameUsage{Sessions: 3, Days: []string{"2026-10-20"}, Last: ptr("2026-10-20")}
	claude.Hook[hookHashOf("Stop", "echo ran")] = usage.HookTotals{Runs: 7, Ms: 70, Timed: 7, Errors: 2, Last: ptr("2026-10-25")}
	return &usage.Totals{Claude: claude, Codex: empty()}
}

func (f cellsFixture) windows() *usage.Windows {
	return &usage.Windows{
		Claude: usage.LogWindow{Files: 9, Oldest: ptr("2026-09-01"), Newest: &f.newestLog},
		Codex:  usage.LogWindow{Files: 2, Oldest: ptr("2026-09-15"), Newest: &f.newestLog},
	}
}

func (f cellsFixture) ready() Snapshot {
	return AttachUsage(f.inventory, &usage.Input{State: "ready", Totals: f.totals(), Windows: f.windows()}, f.now)
}

func cellOf(inv Snapshot, name string, cli CLI, itemCLI CLI) Cell {
	return item(inv, name, itemCLI).Cells.For(cli)
}

// Swift: InventoryTests.swift "usage cells" / "counted, with zero runs meaning never ran"
func TestCellsCounted(t *testing.T) {
	inv := newCellsFixture(t).ready()
	if got, want := cellOf(inv, "both", Claude, Claude), Counted(3, ptr("2026-10-20"), nil); !reflect.DeepEqual(got, want) {
		t.Errorf("both/claude = %+v", got)
	}
	if got, want := cellOf(inv, "both", Codex, Claude), Counted(0, nil, nil); !reflect.DeepEqual(got, want) {
		t.Errorf("both/codex = %+v", got)
	}
	if got, want := cellOf(inv, "only-claude", Claude, Claude), Counted(0, nil, nil); !reflect.DeepEqual(got, want) {
		t.Errorf("only-claude = %+v", got)
	}
}

// A Codex skill is logged under its folder name; the row is named after the frontmatter name.
func TestCellsCountedByFolderName(t *testing.T) {
	h := newTempHome(t)
	for _, folder := range []string{"pdf-tools", "same-name"} {
		name := folder
		if folder == "pdf-tools" {
			name = "PDF Tools"
		}
		h.setModified(h.write(".codex/skills/"+folder+"/SKILL.md", skillFile(name)), "2026-09-20T00:00:00Z")
	}
	f := cellsFixture{inventory: Read(h.roots()), now: mustTime(t, "2026-11-02T12:00:00Z")}
	f.newestLog = mustTime(t, "2026-10-29T00:00:00Z").UnixMilli()
	totals := f.totals()
	totals.Codex.Skill["pdf-tools"] = usage.NameUsage{Sessions: 4, Last: ptr("2026-10-21")}
	totals.Codex.Skill["PDF Tools"] = usage.NameUsage{Sessions: 1, Last: ptr("2026-10-01")}
	totals.Codex.Skill["same-name"] = usage.NameUsage{Sessions: 2, Last: ptr("2026-10-22")}
	inv := AttachUsage(f.inventory, &usage.Input{State: "ready", Totals: totals, Windows: f.windows()}, f.now)
	if got, want := cellOf(inv, "PDF Tools", Codex, Codex), Counted(4, ptr("2026-10-21"), nil); !reflect.DeepEqual(got, want) {
		t.Errorf("pdf-tools = %+v, want the folder-name count (larger, not summed)", got)
	}
	if got, want := cellOf(inv, "same-name", Codex, Codex), Counted(2, ptr("2026-10-22"), nil); !reflect.DeepEqual(got, want) {
		t.Errorf("same-name = %+v", got)
	}
}

// Swift: InventoryTests.swift "usage cells" / "missing when not installed in that CLI; both rows of one skill show the same cells"
func TestCellsMissing(t *testing.T) {
	inv := newCellsFixture(t).ready()
	if got := cellOf(inv, "only-claude", Codex, Claude); !got.IsMissing() {
		t.Errorf("only-claude/codex = %+v", got)
	}
	if got, want := cellOf(inv, "both", Claude, Codex), cellOf(inv, "both", Claude, Claude); !reflect.DeepEqual(got, want) {
		t.Errorf("the codex row shows %+v, the claude row %+v", got, want)
	}
}

// Swift: InventoryTests.swift "usage cells" / "pending when no log window covers the item yet"
func TestCellsPending(t *testing.T) {
	inv := newCellsFixture(t).ready()
	if got := cellOf(inv, "after-log", Claude, Claude); got.State != StatePending || got.Reason != "Added after the newest log" {
		t.Errorf("after-log = %+v", got)
	}
	if got := cellOf(inv, "fresh", Claude, Claude); got.State != StatePending || got.Reason != "Added in the last 24 hours" {
		t.Errorf("fresh = %+v", got)
	}
}

// Swift: InventoryTests.swift "usage cells" / "pending for everything until the scan has finished, and when a CLI has no logs"
func TestCellsPendingWithoutScan(t *testing.T) {
	f := newCellsFixture(t)
	scanning := usage.Scanning
	waiting := AttachUsage(f.inventory, &scanning, f.now)
	if got := cellOf(waiting, "both", Claude, Claude); !reflect.DeepEqual(got, Pending("Usage scan has not finished")) {
		t.Errorf("scanning = %+v", got)
	}
	noCodexLogs := f.windows()
	noCodexLogs.Codex = usage.LogWindow{}
	none := AttachUsage(f.inventory, &usage.Input{State: "ready", Totals: f.totals(), Windows: noCodexLogs}, f.now)
	if got := cellOf(none, "both", Codex, Codex); !reflect.DeepEqual(got, Pending("No logs scanned for this CLI yet")) {
		t.Errorf("no codex logs = %+v", got)
	}
	nothing := AttachUsage(f.inventory, nil, f.now)
	if got := cellOf(nothing, "both", Claude, Claude); !reflect.DeepEqual(got, Pending("Usage scan has not finished")) {
		t.Errorf("nil usage = %+v", got)
	}
}

// Swift: InventoryTests.swift "usage cells" / "hooks: Claude counted with errors, Codex unmeasurable, an absent CLI missing"
func TestCellsHooks(t *testing.T) {
	inv := newCellsFixture(t).ready()
	ran := hookByCommand(inv, "echo ran")
	if want := Counted(7, ptr("2026-10-25"), ptr(2)); !reflect.DeepEqual(ran.Cells.Claude, want) || !ran.Cells.Codex.IsMissing() {
		t.Errorf("ran cells = %+v", ran.Cells)
	}
	if want := (&HookUsage{Runs: 7, AvgMs: ptr(10), TotalMs: 70, Errors: 2, Last: ptr("2026-10-25")}); !reflect.DeepEqual(ran.Usage, want) {
		t.Errorf("ran usage = %+v", ran.Usage)
	}
	codexOnly := hookByCommand(inv, "echo codex-only")
	if !reflect.DeepEqual(codexOnly.Cells.Codex, Unmeasurable("Codex does not log hook runs")) || !codexOnly.Cells.Claude.IsMissing() || codexOnly.Usage != nil {
		t.Errorf("codex-only = %+v", codexOnly)
	}
}

// Swift: InventoryTests.swift "usage cells" / "filter counts: all, only in one CLI, never ran, dead"
func TestFilterCounts(t *testing.T) {
	inv := newCellsFixture(t).ready()
	if got, want := FilterCountsOf(inv.Items, inv.Hooks), (FilterCounts{All: 7, Only: OnlyCLIs{Claude: 5, Codex: 1}, NeverRan: 1, Dead: 1}); got != want {
		t.Errorf("counts = %+v, want %+v", got, want)
	}
	if got := FilterCountsOfRows(nil); got != (FilterCounts{}) {
		t.Errorf("empty = %+v", got)
	}
}

// Swift: InventoryTests.swift "usage cells" / "a dead hook with zero runs is counted under dead only"
func TestDeadOnly(t *testing.T) {
	row := FilterRow{Key: "k", CLI: Claude, Dead: true, Cells: &Cells{Claude: Counted(0, nil, nil), Codex: Missing()}}
	if got := FilterCountsOfRows([]FilterRow{row}); got.Dead != 1 || got.NeverRan != 0 {
		t.Errorf("counts = %+v", got)
	}
}

// Extra (G2.1): without cells a row counts for its own CLI, or both when it exists in the other too.
func TestFilterCountsWithoutCells(t *testing.T) {
	rows := []FilterRow{
		{Key: "a", CLI: Claude}, {Key: "b", CLI: Codex}, {Key: "c", CLI: Claude, InOther: true},
	}
	if got := FilterCountsOfRows(rows); got.All != 3 || got.Only.Claude != 1 || got.Only.Codex != 1 {
		t.Errorf("counts = %+v", got)
	}
}
