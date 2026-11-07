package inventory

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/usage"
)

// loadout.rows is new in the Go core (it replaces Inventory.read + attachUsage + filterCounts in the shell),
// so these tests are the extra vectors of G2.1, built from LoadoutData.build and LoadoutRows.build.

func rowsHome(t *testing.T) tempHome {
	t.Helper()
	h := newTempHome(t)
	alpha := h.path("work/alpha")
	h.write(".claude/skills/both/SKILL.md", skillFile("both"))
	h.write(".codex/skills/both/SKILL.md", skillFile("both"))
	h.write(".claude/skills/solo/SKILL.md", skillFile("solo"))
	h.write(".claude/settings.json", `{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "sh '`+h.root+`/gone/dead.sh'"}, {"type": "command", "command": "echo live"}]}]}}`)
	h.write(".claude/projects/-enc-alpha/s1.jsonl", `{"type":"user","cwd":"`+alpha+`"}`+"\n")
	h.write("work/alpha/.claude/skills/pskill/SKILL.md", skillFile("pskill"))
	h.write(".codex/sessions/2026/r.jsonl", "{}\n")
	// Config files are older than the newest log, so a zero is "never ran", not "pending".
	for _, rel := range []string{".claude/skills/both/SKILL.md", ".codex/skills/both/SKILL.md", ".claude/skills/solo/SKILL.md", ".claude/settings.json", "work/alpha/.claude/skills/pskill/SKILL.md"} {
		h.setModified(h.path(rel), "2026-09-20T00:00:00Z")
	}
	for _, rel := range []string{".claude/projects/-enc-alpha/s1.jsonl", ".codex/sessions/2026/r.jsonl"} {
		h.setModified(h.path(rel), "2026-10-29T00:00:00Z")
	}
	return h
}

func TestLoadoutRowsScanning(t *testing.T) {
	h := rowsHome(t)
	r := h.roots()
	rows := BuildLoadoutRows(Read(r), usage.Scanning, mustTime(t, "2026-11-02T00:00:00Z"))
	if rows.Usage != "scanning" {
		t.Errorf("usage = %q", rows.Usage)
	}
	for _, it := range rows.Items {
		if it.Cells == nil {
			t.Fatalf("%s has no cells", it.ID)
		}
		for _, cli := range usage.CLIs {
			if c := it.Cells.For(cli); !c.IsMissing() && c.State != StatePending {
				t.Errorf("%s %s = %+v, want pending or missing while scanning", it.ID, cli, c)
			}
		}
	}
	for _, hk := range rows.Hooks {
		if hk.Usage != nil {
			t.Errorf("hook usage %+v while scanning", hk.Usage)
		}
	}
	alpha := h.path("work/alpha")
	if len(rows.CountsByScope) != 2 || rows.CountsByScope[GlobalScope].All != 4 || rows.CountsByScope[alpha].All != 1 {
		t.Errorf("countsByScope = %+v", rows.CountsByScope)
	}
	if rows.CountsByScope[GlobalScope].Dead != 1 {
		t.Errorf("global counts = %+v, want the dead hook counted", rows.CountsByScope[GlobalScope])
	}
}

func TestLoadoutRowsFlags(t *testing.T) {
	h := rowsHome(t)
	r := h.roots()
	input := usage.Ready(scanOf(t, r))
	rows := BuildLoadoutRows(Read(r), input, mustTime(t, "2026-12-01T00:00:00Z"))
	if rows.Usage != "ready" {
		t.Errorf("usage = %q", rows.Usage)
	}
	// "both" exists in both CLIs and ran nowhere: not one-sided, never ran. "solo" is Claude-only.
	if got := rows.RowFlags["skill::both"]; got != (RowFlags{NeverRan: true}) {
		t.Errorf("both flags = %+v", got)
	}
	if got := rows.RowFlags["skill::solo"]; !got.One || got.Dead {
		t.Errorf("solo flags = %+v", got)
	}
	var dead, live string
	for _, hk := range rows.Hooks {
		if hk.Dead {
			dead = hk.Key()
		} else {
			live = hk.Key()
		}
	}
	if got := rows.RowFlags[dead]; !got.Dead || got.NeverRan {
		t.Errorf("dead hook flags = %+v (a dead hook is counted only under dead)", got)
	}
	if got := rows.RowFlags[live]; !got.One || !got.NeverRan {
		t.Errorf("live hook flags = %+v", got)
	}
	// rowFlags cover every item and hook key.
	for _, it := range rows.Items {
		if _, ok := rows.RowFlags[it.Key()]; !ok {
			t.Errorf("no flags for %s", it.Key())
		}
	}
}

func TestLoadoutRowsJSONShape(t *testing.T) {
	h := rowsHome(t)
	rows := BuildLoadoutRows(Read(h.roots()), usage.Scanning, mustTime(t, "2026-11-02T00:00:00Z"))
	data, err := json.Marshal(rows)
	if err != nil {
		t.Fatal(err)
	}
	var top map[string]any
	if err := json.Unmarshal(data, &top); err != nil {
		t.Fatal(err)
	}
	var keys []string
	for k := range top {
		keys = append(keys, k)
	}
	for _, want := range []string{"usage", "items", "hooks", "problems", "events", "roots", "countsByScope", "rowFlags"} {
		if _, ok := top[want]; !ok {
			t.Errorf("missing %q in %v", want, keys)
		}
	}
	if len(top) != 8 {
		t.Errorf("keys = %v", keys)
	}
	flags := top["rowFlags"].(map[string]any)["skill::solo"].(map[string]any)
	if _, ok := flags["one"]; !ok || len(flags) != 3 {
		t.Errorf("flags = %v", flags)
	}
}

// loadout.rows through the service: it attaches the usage state of the process, or reports scanning.
func TestServiceRows(t *testing.T) {
	h := rowsHome(t)
	r := h.roots()
	scanner := usage.NewScanner(r)
	svc := NewService(r, scanner)
	svc.Now = func() time.Time { return mustTime(t, "2026-12-01T00:00:00Z") }
	ctx := t.Context()

	before, err := svc.Rows(ctx)
	if err != nil || before.Usage != "scanning" {
		t.Fatalf("before the scan: %q, %v", before.Usage, err)
	}
	if _, err := scanner.Scan(ctx, nil); err != nil {
		t.Fatal(err)
	}
	after, err := svc.Rows(ctx)
	if err != nil || after.Usage != "ready" {
		t.Fatalf("after the scan: %q, %v", after.Usage, err)
	}
	if reflect.DeepEqual(before.Items[0].Cells, after.Items[0].Cells) {
		t.Error("the cells did not change when the scan finished")
	}
	// inventory.read has no cells and null hook usage, whatever the scan state.
	snap, err := svc.Read(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range snap.Items {
		if it.Cells != nil {
			t.Errorf("%s has cells", it.ID)
		}
	}
	for _, hk := range snap.Hooks {
		if hk.Cells != nil || hk.Usage != nil {
			t.Errorf("hook %s has cells or usage", hk.ID)
		}
	}
	data, _ := json.Marshal(snap)
	if !strings.Contains(string(data), `"usage":null`) || strings.Contains(string(data), `"cells"`) {
		t.Errorf("inventory.read wire form: %s", data)
	}

	cancelled, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := svc.Read(cancelled); err == nil {
		t.Error("a cancelled read succeeded")
	}
}

// The project list is process state: Read refreshes it, Projects discovers once when it is empty, and an
// unknown folder is not in it (the rules methods check against it).
func TestServiceProjects(t *testing.T) {
	h := rowsHome(t)
	r := h.roots()
	svc := NewService(r, nil)
	got, err := svc.Projects(t.Context())
	alpha := h.path("work/alpha")
	if err != nil || !reflect.DeepEqual(got, []string{alpha}) {
		t.Fatalf("projects = %q, %v", got, err)
	}
	// A project that appears later is not listed until Read refreshes the list.
	h.write(".claude/projects/-enc-beta/s1.jsonl", `{"type":"user","cwd":"`+h.path("work/beta")+`"}`+"\n")
	h.write("work/beta/.claude/skills/b/SKILL.md", skillFile("b"))
	if got, _ := svc.Projects(t.Context()); len(got) != 1 {
		t.Errorf("projects before refresh = %q", got)
	}
	if _, err := svc.Read(t.Context()); err != nil {
		t.Fatal(err)
	}
	if got, _ := svc.Projects(t.Context()); len(got) != 2 {
		t.Errorf("projects after refresh = %q", got)
	}
	cancelled, cancel := context.WithCancel(t.Context())
	cancel()
	fresh := NewService(r, nil)
	if _, err := fresh.Projects(cancelled); err == nil {
		t.Error("a cancelled discovery succeeded")
	}
	// Rows without a usage source reports scanning.
	rows, err := svc.Rows(t.Context())
	if err != nil || rows.Usage != "scanning" {
		t.Errorf("rows = %q, %v", rows.Usage, err)
	}
}
