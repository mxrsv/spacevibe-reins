package clis

// PerCLI is an element of a wire array of {cli, …} objects: every per-CLI value on the wire is one (spec MC-R2). The
// arrays follow the registry order and hold at most one element per CLI.
type PerCLI interface {
	// CLIID is the CLI the element belongs to.
	CLIID() ID
}

// Find is the element of id in entries, false when entries hold none. It never answers with another CLI's element.
func Find[E PerCLI](entries []E, id ID) (E, bool) {
	for _, e := range entries {
		if e.CLIID() == id {
			return e, true
		}
	}
	var zero E
	return zero, false
}
