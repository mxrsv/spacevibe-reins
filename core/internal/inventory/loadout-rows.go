package inventory

import (
	"slices"
	"time"

	"spacevibe.dev/core/internal/usage"
)

// GlobalScope is the countsByScope key of user-level configuration.
const GlobalScope = "global"

// RowFlags are the chips a matrix row sets: One (present in one CLI only), NeverRan and Dead. They are the
// filter counts over that row's members, each count above zero.
type RowFlags struct {
	One      bool `json:"one"`
	NeverRan bool `json:"neverRan"`
	Dead     bool `json:"dead"`
}

// LoadoutRows is the loadout.rows result: one inventory read with the usage state attached, the filter
// counts of every scope, and the flags of every row key. Grouping rows by key, sorting and labels stay in the
// shell. Problems are the raw sentences; the shell shortens the home folder in them.
type LoadoutRows struct {
	// Usage is "scanning" until a scan has finished in this process, then "ready".
	Usage         string                  `json:"usage"`
	Items         []Item                  `json:"items"`
	Hooks         []Hook                  `json:"hooks"`
	Problems      []string                `json:"problems"`
	Events        map[string][]string     `json:"events"`
	Roots         map[string]string       `json:"roots"`
	CountsByScope map[string]FilterCounts `json:"countsByScope"`
	RowFlags      map[string]RowFlags     `json:"rowFlags"`
}

// BuildLoadoutRows is LoadoutData.build and the per-row flags of LoadoutRows.build, from one raw snapshot and
// one usage state. Pure apart from file mtimes.
func BuildLoadoutRows(raw Snapshot, in usage.Input, now time.Time) LoadoutRows {
	return buildLoadoutRows(raw, in, now, nil)
}

// buildLoadoutRows is BuildLoadoutRows with the first-seen times of the store (ms by item id; see attachUsage).
func buildLoadoutRows(raw Snapshot, in usage.Input, now time.Time, firstSeen map[string]float64) LoadoutRows {
	attached := attachUsage(raw, &in, now, firstSeen)

	scopes := []string{GlobalScope}
	var projects []string
	for _, item := range attached.Items {
		if item.Project != nil {
			projects = append(projects, *item.Project)
		}
	}
	for _, hook := range attached.Hooks {
		if hook.Project != nil {
			projects = append(projects, *hook.Project)
		}
	}
	slices.Sort(projects)
	scopes = append(scopes, slices.Compact(projects)...)

	counts := make(map[string]FilterCounts, len(scopes))
	for _, scope := range scopes {
		var project *string
		if scope != GlobalScope {
			project = &scope
		}
		var items []Item
		for _, item := range attached.Items {
			if sameProject(item.Project, project) {
				items = append(items, item)
			}
		}
		var hooks []Hook
		for _, hook := range attached.Hooks {
			if sameProject(hook.Project, project) {
				hooks = append(hooks, hook)
			}
		}
		counts[scope] = FilterCountsOf(items, hooks)
	}

	byKey := map[string][]FilterRow{}
	for _, item := range attached.Items {
		byKey[item.Key()] = append(byKey[item.Key()], ItemFilterRow(item))
	}
	for _, hook := range attached.Hooks {
		byKey[hook.Key()] = append(byKey[hook.Key()], HookFilterRow(hook))
	}
	flags := make(map[string]RowFlags, len(byKey))
	for key, rows := range byKey {
		c := FilterCountsOfRows(rows)
		flags[key] = RowFlags{One: c.Only.Claude+c.Only.Codex > 0, NeverRan: c.NeverRan > 0, Dead: c.Dead > 0}
	}

	return LoadoutRows{
		Usage: in.State, Items: attached.Items, Hooks: attached.Hooks, Problems: attached.Problems,
		Events: attached.Events, Roots: attached.Roots, CountsByScope: counts, RowFlags: flags,
	}
}

func sameProject(a, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}
