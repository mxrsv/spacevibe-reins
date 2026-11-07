package inventory

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/goldentest"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/usage"
)

// fixtureRoots points every root at the shared fixture tree, with a private data folder so the scan cache
// never lands in the shared tree.
func fixtureRoots(t testing.TB) (roots.Roots, string) {
	t.Helper()
	root, err := goldentest.Materialize()
	if err != nil {
		t.Fatal(err)
	}
	env := goldentest.Env(root)
	env["SPACEVIBE_HOME"] = t.TempDir()
	cfg, err := config.LoadFrom(func(k string) string { return env[k] })
	if err != nil {
		t.Fatal(err)
	}
	realHome, err := roots.RealHome()
	if err != nil {
		t.Fatal(err)
	}
	r, err := roots.Resolve(cfg, realHome)
	if err != nil {
		t.Fatal(err)
	}
	return r, root
}

func fixtureNow(t testing.TB) time.Time {
	t.Helper()
	now, err := goldentest.Now()
	if err != nil {
		t.Fatal(err)
	}
	return now
}

// tokenHome is the home-token projection for a tree that holds json.Number: goldentest.HomeToken would turn a
// json.Number (a string kind) into a plain string, so numbers are carried over untouched here.
func tokenHome(v any, root string) any {
	switch x := v.(type) {
	case string:
		return goldentest.HomeTokenString(x, root)
	case []any:
		out := make([]any, len(x))
		for i, item := range x {
			out[i] = tokenHome(item, root)
		}
		return out
	case map[string]any:
		out := make(map[string]any, len(x))
		for k, item := range x {
			out[goldentest.HomeTokenString(k, root)] = tokenHome(item, root)
		}
		return out
	}
	return v
}

// sortedByID is the inventory-sorted projection: inventory.items and inventory.hooks ordered by id (Swift
// sorts with `<` on the id strings, which are ASCII hex and lowercase words here).
func sortedByID(t testing.TB, tree any) any {
	t.Helper()
	top, ok := tree.(map[string]any)
	if !ok {
		t.Fatal("golden is not an object")
	}
	inv, ok := top["inventory"].(map[string]any)
	if !ok {
		t.Fatal("golden has no inventory object")
	}
	for _, key := range []string{"items", "hooks"} {
		list, ok := inv[key].([]any)
		if !ok {
			t.Fatalf("inventory.%s is not an array", key)
		}
		sorted := slices.Clone(list)
		slices.SortStableFunc(sorted, func(a, b any) int {
			return strings.Compare(a.(map[string]any)["id"].(string), b.(map[string]any)["id"].(string))
		})
		inv[key] = sorted
	}
	return top
}

// Swift: InventoryTests.swift "the inventory with usage attached equals inventory.json from the Node core"
// Projection inventory-sorted: items and hooks by id; the root path becomes $HOME.
func TestGoldenInventory(t *testing.T) {
	r, root := fixtureRoots(t)
	manifest, err := goldentest.LoadManifest()
	if err != nil {
		t.Fatal(err)
	}
	snapshot := Read(r)
	input := usage.Ready(scanOf(t, r))
	attached := AttachUsage(snapshot, &input, fixtureNow(t))
	got := map[string]any{
		"now":          json.Number(jsonNumber(manifest.Now)),
		"usageInput":   jsonTree(t, input),
		"inventory":    jsonTree(t, attached),
		"filterCounts": jsonTree(t, FilterCountsOf(attached.Items, attached.Hooks)),
	}
	want, err := goldentest.LoadGolden("inventory")
	if err != nil {
		t.Fatal(err)
	}
	goldentest.AssertCanonicalEqual(t, "inventory-sorted", sortedByID(t, want), sortedByID(t, tokenHome(got, root)))
	goldentest.AssertCaseCount(t, "inventory golden items", len(attached.Items), 20)
	goldentest.AssertCaseCount(t, "inventory golden hooks", len(attached.Hooks), 9)
	// The same fixture through loadout.rows: the golden's counts cover every scope; each scope's counts are the
	// counts of the rows that sit in it.
	rows := BuildLoadoutRows(snapshot, input, fixtureNow(t))
	var globalItems []Item
	for _, it := range attached.Items {
		if it.Project == nil {
			globalItems = append(globalItems, it)
		}
	}
	var globalHooks []Hook
	for _, hk := range attached.Hooks {
		if hk.Project == nil {
			globalHooks = append(globalHooks, hk)
		}
	}
	if want := FilterCountsOf(globalItems, globalHooks); rows.CountsByScope[GlobalScope] != want {
		t.Errorf("global counts = %+v, want %+v", rows.CountsByScope[GlobalScope], want)
	}
	if rows.Usage != "ready" || len(rows.RowFlags) == 0 {
		t.Errorf("rows = %q, %d flags", rows.Usage, len(rows.RowFlags))
	}
}

func jsonNumber(f float64) string {
	data, _ := json.Marshal(f)
	return string(data)
}
