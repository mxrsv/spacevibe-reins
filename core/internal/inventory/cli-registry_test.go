package inventory

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"slices"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/roots"
)

func TestInventoryAdaptersMatchRegistry(t *testing.T) {
	if err := adapters.Check(); err != nil {
		t.Fatal(err)
	}
}

// Every CLI with the inventory concept has one element, in registry order, in each wire array: the cells of every
// row, the filter counts' only, the snapshot's events and roots.
func TestEveryInventoryCLIIsInEachArray(t *testing.T) {
	want := clis.IDsWith(clis.Inventory)
	h := newTempHome(t)
	h.write(".claude/skills/one/SKILL.md", skillFile("one"))
	h.write(".codex/hooks.json", hookConfig("Stop", "echo codex"))
	inv := AttachUsage(Read(h.roots()), nil, mustTime(t, "2026-11-02T00:00:00Z"))
	idsOf := func(name string, n int, at func(int) clis.ID) {
		t.Helper()
		got := make([]clis.ID, n)
		for i := range got {
			got[i] = at(i)
		}
		if !slices.Equal(got, want) {
			t.Errorf("%s lists %v, want %v", name, got, want)
		}
	}
	for _, it := range inv.Items {
		idsOf("item cells", len(it.Cells), func(i int) clis.ID { return it.Cells[i].CLI })
	}
	for _, hk := range inv.Hooks {
		idsOf("hook cells", len(hk.Cells), func(i int) clis.ID { return hk.Cells[i].CLI })
	}
	if len(inv.Items) == 0 || len(inv.Hooks) == 0 {
		t.Fatalf("fixture: %d items, %d hooks", len(inv.Items), len(inv.Hooks))
	}
	idsOf("events", len(inv.Events), func(i int) clis.ID { return inv.Events[i].CLI })
	idsOf("roots", len(inv.Roots), func(i int) clis.ID { return inv.Roots[i].CLI })
	only := FilterCountsOf(inv.Items, inv.Hooks).Only
	idsOf("only", len(only), func(i int) clis.ID { return only[i].CLI })
}

// The old Cells.For answered Codex's cell for any id that was not Claude Code; events and the hook-log rule of a CLI
// without an inventory adapter are errors, never another CLI's.
func TestAnotherCLIIsNotReadAsCodex(t *testing.T) {
	cells := Cells{{CLI: Claude, State: StateMissing}, {CLI: Codex, State: StateCounted, Runs: 3}}
	for _, c := range []struct {
		id   clis.ID
		want error
	}{{clis.Gemini, clis.ErrConceptAbsent}, {"nope", clis.ErrUnknownCLI}} {
		if cell, ok := cells.For(c.id); ok {
			t.Errorf("Cells.For(%s) = %+v", c.id, cell)
		}
		if _, err := EventsOf(c.id); !errors.Is(err, c.want) {
			t.Errorf("EventsOf(%s) = %v, want %v", c.id, err, c.want)
		}
		if _, err := UnloggedHooks(c.id); !errors.Is(err, c.want) {
			t.Errorf("UnloggedHooks(%s) = %v, want %v", c.id, err, c.want)
		}
	}
	if _, has := clis.Find(Events(), clis.Gemini); has {
		t.Error("Events lists gemini, which has no inventory")
	}
	if k, err := KindsOf(clis.Gemini); err != nil || k.Of(KindSkill).Support != SupportAbsent {
		t.Errorf("KindsOf(gemini) = %v, %v: a CLI without inventory has every kind absent", k, err)
	}
	if _, err := KindsOf("nope"); !errors.Is(err, clis.ErrUnknownCLI) {
		t.Errorf("KindsOf(nope) = %v", err)
	}
}

// Each adapter's declaration is whole and consistent: every item kind is declared; runs are set exactly when the kind
// is not absent, with a reason exactly when not logged; events only on hooks; and full support only for a CLI
// SpaceVibe writes. A read-only kind may still name a copy format: a copy out of it writes only the target.
func TestKindDeclarationsAreConsistent(t *testing.T) {
	for _, a := range adapters.InOrder() {
		d, err := clis.Lookup(a.ID)
		if err != nil {
			t.Fatal(err)
		}
		kinds := a.Adapter.kinds()
		for kind := range kinds {
			if !slices.Contains(ItemKinds, kind) {
				t.Errorf("%s declares %s, which ItemKinds lacks", a.ID, kind)
			}
		}
		for _, kind := range ItemKinds {
			k, declared := kinds[kind]
			if !declared {
				t.Errorf("%s does not declare %s: list it, as absent if the CLI has none", a.ID, kind)
				continue
			}
			switch {
			case k.Support == SupportAbsent && (k.Runs != "" || k.CopyFormat != "" || k.Events != nil):
				t.Errorf("%s %s is absent but declares runs, a copy format or events", a.ID, kind)
			case k.Support != SupportAbsent && k.Runs != RunsCounted && k.Runs != RunsNotLogged:
				t.Errorf("%s %s has runs %q", a.ID, kind, k.Runs)
			case (k.Runs == RunsNotLogged) != (k.NotLoggedReason != ""):
				t.Errorf("%s %s: a not-logged reason goes with runs notLogged, and only with it", a.ID, kind)
			case (kind == KindHook && k.Support != SupportAbsent) != (len(k.Events) > 0):
				t.Errorf("%s %s: events belong to a present hook kind, and only to it", a.ID, kind)
			case k.Support == SupportFull && !d.Has(clis.Mutate):
				t.Errorf("%s %s is full but the CLI has no mutate concept", a.ID, kind)
			}
		}
	}
}

// Today Claude Code and Codex have every kind, so no cell of theirs is absent, and hook runs are counted only where
// the CLI logs them (Codex does not).
func TestShippedKinds(t *testing.T) {
	for _, id := range clis.IDsWith(clis.Inventory) {
		kinds, err := KindsOf(id)
		if err != nil {
			t.Fatal(err)
		}
		for _, kind := range ItemKinds {
			if kinds.Of(kind).Support != SupportFull {
				t.Errorf("%s %s = %s, want full", id, kind, kinds.Of(kind).Support)
			}
		}
	}
	if reason, _ := UnloggedHooks(Codex); reason != CodexHooksReason {
		t.Errorf("codex hooks reason = %q", reason)
	}
	if reason, _ := UnloggedHooks(Claude); reason != "" {
		t.Errorf("claude hooks reason = %q", reason)
	}
}

// noHooksInventory is a test-only CLI that has skills and agents but no hooks at all.
type noHooksInventory struct{ codexInventory }

func (noHooksInventory) kinds() Kinds {
	return Kinds{
		KindSkill: {Support: SupportReadOnly, Runs: RunsCounted},
		KindAgent: {Support: SupportReadOnly, Runs: RunsCounted},
		KindHook:  {Support: SupportAbsent},
	}
}

const noHooks clis.ID = "nohooks"

// withNoHooksCLI adds noHooksInventory to a copy of the registry and to the adapter table for one test.
func withNoHooksCLI(t *testing.T) {
	t.Helper()
	registry := clis.Default().Plus(clis.Descriptor{
		ID: noHooks, Label: "No Hooks", Layout: clis.Layout{Folder: ".nohooks", Skills: "skills"}, Concepts: []clis.Concept{clis.Inventory},
	})
	saved := adapters
	adapters = clis.NewAdaptersIn(registry, clis.Inventory, map[clis.ID]inventoryAdapter{
		clis.Claude: claudeInventory{}, clis.Codex: codexInventory{}, noHooks: noHooksInventory{},
	})
	t.Cleanup(func() { adapters = saved })
	if err := adapters.Check(); err != nil {
		t.Fatal(err)
	}
}

// MC-R5 acceptance: a registry CLI that lacks hooks gets absent hook cells, not missing ones, while a skill it does not
// hold is missing (it has skills). Absent is never counted as present, so a hook in Claude Code alone stays "only in
// one CLI".
func TestACLIWithoutHooksGetsAbsentCells(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/skills/one/SKILL.md", skillFile("one"))
	h.write(".claude/settings.json", hookConfig("Stop", "echo claude"))
	snapshot := Read(h.roots())
	withNoHooksCLI(t)
	inv := AttachUsage(snapshot, nil, mustTime(t, "2026-11-02T00:00:00Z"))
	hook := hookByCommand(inv, "echo claude")
	if hook == nil {
		t.Fatal("fixture: no hook")
	}
	if got := cellIn(hook.Cells, noHooks); got.State != StateAbsent {
		t.Errorf("hook cell of the CLI without hooks = %+v, want absent", got)
	}
	if got := cellIn(hook.Cells, Codex); got.State != StateMissing {
		t.Errorf("hook cell of Codex = %+v, want missing", got)
	}
	if got := cellIn(item(inv, "one").Cells, noHooks); got.State != StateMissing {
		t.Errorf("skill cell of the CLI without hooks = %+v, want missing", got)
	}
	data, err := json.Marshal(hook.Cells)
	if err != nil || !strings.Contains(string(data), `{"cli":"nohooks","state":"absent"}`) {
		t.Errorf("cells on the wire = %s, %v", data, err)
	}
	var back Cells
	if err := json.Unmarshal(data, &back); err != nil || !reflect.DeepEqual(back, hook.Cells) {
		t.Errorf("round trip = %+v, %v", back, err)
	}
	counts := FilterCountsOf(nil, []Hook{*hook})
	if only, _ := clis.Find(counts.Only, Claude); only.Count != 1 {
		t.Errorf("only = %+v: an absent cell must not count as present", counts.Only)
	}
}

// MC28: hook rows match across CLIs only on identical event names. The same command under the same event in Claude
// Code and Codex is one row; under event names that differ only in case it is two rows, never mapped to each other.
func TestHookRowsMatchOnlyOnIdenticalEvents(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/settings.json", `{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "echo same"}]}], `+
		`"Stop": [{"hooks": [{"type": "command", "command": "echo cased"}]}]}}`)
	h.write(".codex/hooks.json", `{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "echo same"}]}], `+
		`"stop": [{"hooks": [{"type": "command", "command": "echo cased"}]}]}}`)
	inv := AttachUsage(Read(h.roots()), nil, mustTime(t, "2026-11-02T00:00:00Z"))
	keys := map[string]map[string]bool{}
	for _, hk := range inv.Hooks {
		if keys[hk.Command] == nil {
			keys[hk.Command] = map[string]bool{}
		}
		keys[hk.Command][hk.Key()] = true
	}
	if len(keys["echo same"]) != 1 {
		t.Errorf("PreToolUse in both CLIs gave %d rows, want 1", len(keys["echo same"]))
	}
	if len(keys["echo cased"]) != 2 {
		t.Errorf("Stop and stop gave %d rows, want 2", len(keys["echo cased"]))
	}
	for _, hk := range inv.Hooks {
		if hk.Command == "echo cased" {
			other := Codex
			if hk.CLI == Codex {
				other = Claude
			}
			if got := cellIn(hk.Cells, other); got.State != StateMissing {
				t.Errorf("%s %s: the other CLI's cell is %+v, want missing", hk.CLI, hk.Event, got)
			}
		}
	}
}

// otherProjectsCLI is a second CLI with a project folder (.other) that names the given candidates.
type otherProjectsCLI struct {
	codexInventory
	candidates []string
}

func (o otherProjectsCLI) projectCandidates(context.Context, roots.CLIRoots) []string {
	return o.candidates
}
func (otherProjectsCLI) projectFolder() (projectFolder, bool) {
	return projectFolder{Name: ".other"}, true
}

// ProjectFolders is Undo's write containment inside projects, so it lists only the folders discovery found in each
// project. With a second CLI that has project folders, a project with only .claude must not also allow writes under
// <project>/.other, and the other way round.
func TestProjectFoldersListOnlyFoldersThatExist(t *testing.T) {
	h := newTempHome(t)
	claudeOnly, otherOnly, both := h.path("work/claude-only"), h.path("work/other-only"), h.path("work/both")
	h.write("work/claude-only/.claude/settings.json", "{}")
	h.write("work/other-only/.other/settings.json", "{}")
	h.write("work/both/.claude/settings.json", "{}")
	h.write("work/both/.other/settings.json", "{}")
	h.write(".codex/config.toml", "[projects.\""+claudeOnly+"\"]\n[projects.\""+otherOnly+"\"]\n[projects.\""+both+"\"]\n")
	r := h.roots()
	bound, err := bind(r)
	if err != nil {
		t.Fatal(err)
	}
	other, err := r.CLI(clis.Codex)
	if err != nil {
		t.Fatal(err)
	}
	bound = append(bound, boundAdapter{"other", otherProjectsCLI{candidates: []string{claudeOnly, otherOnly, both}}, other})
	got := discoverBound(context.Background(), bound)
	want := []discoveredProject{
		{claudeOnly, []string{claudeOnly + "/.claude"}},
		{otherOnly, []string{otherOnly + "/.other"}},
		{both, []string{both + "/.claude", both + "/.other"}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("discovered = %+v\nwant %+v", got, want)
	}
	// Today, with Claude Code the only CLI with project folders, ProjectFolders is <project>/.claude per project.
	if got, want := ProjectFolders(r), []string{both + "/.claude", claudeOnly + "/.claude"}; !slicesEqualSorted(got, want) {
		t.Errorf("ProjectFolders = %q, want %q", got, want)
	}
}

func slicesEqualSorted(a, b []string) bool {
	a, b = slices.Clone(a), slices.Clone(b)
	slices.Sort(a)
	slices.Sort(b)
	return slices.Equal(a, b)
}
