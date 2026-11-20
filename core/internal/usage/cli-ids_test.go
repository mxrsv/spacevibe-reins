package usage

import "spacevibe.dev/core/internal/clis"

// Short names for the registry ids in this package's tests.
const (
	Claude = clis.Claude
	Codex  = clis.Codex
)

// totalsOf is the totals of one CLI in r; a test that asks for a CLI r lacks is a test bug.
func totalsOf(r Result, cli clis.ID) CLITotals {
	t, err := r.Totals.For(cli)
	if err != nil {
		panic(err)
	}
	return t
}

func windowOf(r Result, cli clis.ID) LogWindow {
	w, err := r.Windows.For(cli)
	if err != nil {
		panic(err)
	}
	return w
}

func sessionsOf(r Result, cli clis.ID) int {
	s, ok := clis.Find(r.Sessions, cli)
	if !ok {
		panic("no sessions for " + string(cli))
	}
	return s.Count
}
