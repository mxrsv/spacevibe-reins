package inventory

import "spacevibe.dev/core/internal/clis"

// Short names for the registry ids in this package's tests.
const (
	Claude = clis.Claude
	Codex  = clis.Codex
)

// cellIn is the cell of cli in cells with its CLI cleared, so a test compares it with a constructor (Counted,
// Missing). A row without a cell for cli is a test bug.
func cellIn(cells Cells, cli clis.ID) Cell {
	cell, ok := cells.For(cli)
	if !ok {
		panic("no cell for " + string(cli))
	}
	cell.CLI = ""
	return cell
}
