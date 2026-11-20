package inventory

import "spacevibe.dev/core/internal/clis"

// FilterRow is the fields FilterCountsOf needs from one row. Items and hooks convert to it; tests build it
// directly.
type FilterRow struct {
	Key   string
	CLI   clis.ID
	Dead  bool
	Cells Cells
}

// ItemFilterRow converts an item.
func ItemFilterRow(i Item) FilterRow {
	return FilterRow{Key: i.Key(), CLI: i.CLI, Cells: i.Cells}
}

// HookFilterRow converts a hook.
func HookFilterRow(h Hook) FilterRow {
	return FilterRow{Key: h.Key(), CLI: h.CLI, Dead: h.Dead, Cells: h.Cells}
}

// FilterCountsOf counts items and hooks for the filter chips. Rows are deduplicated by key, so a skill in
// both CLIs counts once. NeverRan: it ran in no CLI that logs it, and at least one CLI counted it; a dead hook
// is counted only under Dead.
func FilterCountsOf(items []Item, hooks []Hook) FilterCounts {
	rows := make([]FilterRow, 0, len(items)+len(hooks))
	for _, i := range items {
		rows = append(rows, ItemFilterRow(i))
	}
	for _, h := range hooks {
		rows = append(rows, HookFilterRow(h))
	}
	return FilterCountsOfRows(rows)
}

// FilterCountsOfRows is FilterCountsOf over rows. A row with cells is present in every CLI whose cell is neither
// missing nor absent; a row without cells (not attached yet) is present in its own CLI, and rows sharing a key are
// one row present in each of their CLIs.
func FilterCountsOfRows(rows []FilterRow) FilterCounts {
	type group struct {
		clis    map[clis.ID]bool
		counted map[clis.ID]Cell
		dead    bool
	}
	var order []string
	groups := map[string]*group{}
	for _, row := range rows {
		g := groups[row.Key]
		if g == nil {
			g = &group{clis: map[clis.ID]bool{}, counted: map[clis.ID]Cell{}}
			groups[row.Key] = g
			order = append(order, row.Key)
		}
		if row.Cells == nil {
			g.clis[row.CLI] = true
		}
		for _, cell := range row.Cells {
			if cell.IsPresent() {
				g.clis[cell.CLI] = true
				if _, have := g.counted[cell.CLI]; !have {
					g.counted[cell.CLI] = cell
				}
			}
		}
		g.dead = g.dead || row.Dead
	}
	out := FilterCounts{All: len(order)}
	only := map[clis.ID]int{}
	for _, key := range order {
		g := groups[key]
		if len(g.clis) == 1 {
			for cli := range g.clis {
				only[cli]++
			}
		}
		counted, allZero := 0, true
		for _, cell := range g.counted {
			if cell.State == StateCounted {
				counted++
				allZero = allZero && cell.Runs == 0
			}
		}
		if !g.dead && counted > 0 && allZero {
			out.NeverRan++
		}
		if g.dead {
			out.Dead++
		}
	}
	out.Only = OnlyCLIs{}
	for _, a := range adapters.InOrder() {
		out.Only = append(out.Only, OnlyCount{CLI: a.ID, Count: only[a.ID]})
	}
	return out
}
