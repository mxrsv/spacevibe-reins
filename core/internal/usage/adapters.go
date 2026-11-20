package usage

import "spacevibe.dev/core/internal/clis"

// lineParser is one CLI's reading of its session logs: which skills, subagents and hooks a log line shows.
type lineParser interface {
	// parseLine folds one log line into rec. fallbackDay is the log's modification day, for a line with no
	// timestamp.
	parseLine(line []byte, rec *fileRecord, fallbackDay string)
}

// parsers is the usage adapter of every CLI with the usage concept. A CLI without one keeps no countable log:
// its logs are never scanned, and it never borrows another CLI's parser.
var parsers = clis.NewAdapters(clis.Usage, map[clis.ID]lineParser{
	clis.Claude: claudeParser{},
	clis.Codex:  codexParser{},
})
