package limits

import (
	"context"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/roots"
)

// readInput is what a reader may look at: the configuration, every root (the data folder holds the status line
// snapshots), the CLI's own folders and the clock in seconds.
type readInput struct {
	cfg   config.Config
	roots roots.Roots
	cli   roots.CLIRoots
	now   float64
}

// reader reads one CLI's usage-limit windows from its own files.
type reader interface {
	// read is the CLI's entry. The only error is the context's.
	read(ctx context.Context, in readInput) (Entry, error)
	// kind is where the reading comes from.
	kind() ReadingKind
}

// ReadingKind is where a CLI's limits reading comes from. It reaches the shell as `limitsReading` in `clis.list`,
// which decides the Limits wording. The values are the shell's case names.
type ReadingKind string

const (
	// UsageCache: a cache the CLI writes once it has fetched usage, which status line snapshots can supersede
	// (Claude Code).
	UsageCache ReadingKind = "usageCache"
	// LastTurn: the limits the CLI logs after each turn (Codex).
	LastTurn ReadingKind = "lastTurn"
	// NotKept: the CLI keeps no limit on disk; only its folder is checked (Gemini CLI).
	NotKept ReadingKind = "notKept"
)

// KindOf is where the limits reading of cli comes from, or an error wrapping clis.ErrUnknownCLI or
// clis.ErrConceptAbsent.
func KindOf(cli clis.ID) (ReadingKind, error) {
	r, err := readers.For(cli)
	if err != nil {
		return "", err
	}
	return r.kind(), nil
}

// readers is the limits adapter of every CLI with the limits concept. A CLI without one is left out of the result,
// never reported with another CLI's reading.
var readers = clis.NewAdapters(clis.Limits, map[clis.ID]reader{
	clis.Claude: claudeReader{},
	clis.Codex:  codexReader{},
	clis.Gemini: geminiReader{},
})
