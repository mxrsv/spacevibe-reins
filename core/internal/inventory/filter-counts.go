package inventory

// FilterRow is the fields FilterCountsOf needs from one row. Items and hooks convert to it; tests build it
// directly.
type FilterRow struct {
	Key     string
	CLI     CLI
	InOther bool
	Dead    bool
	Cells   *Cells
}

// ItemFilterRow converts an item.
func ItemFilterRow(i Item) FilterRow {
	return FilterRow{Key: i.Key(), CLI: i.CLI, InOther: i.InOther, Cells: i.Cells}
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

// FilterCountsOfRows is FilterCountsOf over rows.
func FilterCountsOfRows(rows []FilterRow) FilterCounts {
	type group struct {
		clis    map[CLI]bool
		counted map[CLI]Cell
		dead    bool
	}
	var order []string
	groups := map[string]*group{}
	for _, row := range rows {
		g := groups[row.Key]
		if g == nil {
			g = &group{clis: map[CLI]bool{}, counted: map[CLI]Cell{}}
			groups[row.Key] = g
			order = append(order, row.Key)
		}
		for _, cli := range [...]CLI{Claude, Codex} {
			if row.Cells != nil {
				cell := row.Cells.For(cli)
				if !cell.IsMissing() {
					g.clis[cli] = true
					if _, have := g.counted[cli]; !have {
						g.counted[cli] = cell
					}
				}
			} else if cli == row.CLI || row.InOther {
				g.clis[cli] = true
			}
		}
		g.dead = g.dead || row.Dead
	}
	out := FilterCounts{All: len(order)}
	for _, key := range order {
		g := groups[key]
		if len(g.clis) == 1 {
			if g.clis[Claude] {
				out.Only.Claude++
			} else {
				out.Only.Codex++
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
	return out
}
