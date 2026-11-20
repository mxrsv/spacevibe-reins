package limits

import (
	"context"

	"spacevibe.dev/core/internal/clis"
)

// geminiReader is Gemini CLI: it keeps no limit on disk, so the entry only says whether its folder exists.
type geminiReader struct{}

func (geminiReader) kind() ReadingKind { return NotKept }

func (geminiReader) read(_ context.Context, in readInput) (Entry, error) {
	return Entry{CLI: clis.Gemini, State: folderState(in.cli.Root, NotMeasurable)}, nil
}
