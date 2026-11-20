package limits

import (
	"context"
	"testing"
	"time"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/roots"
)

func TestReadersMatchRegistry(t *testing.T) {
	if err := readers.Check(); err != nil {
		t.Fatal(err)
	}
}

// A Roots without a registry CLI's folders is an error, never a reading of empty paths.
func TestReadNeedsEveryCLIFolder(t *testing.T) {
	h := newTempHome(t)
	r := h.roots()
	partial := roots.Roots{Data: r.Data, CLIs: map[clis.ID]roots.CLIRoots{clis.Claude: r.CLIs[clis.Claude], clis.Codex: r.CLIs[clis.Codex]}}
	if _, err := Read(context.Background(), h.cfg(), partial, time.Now()); err == nil {
		t.Fatal("Read without Gemini CLI's folder succeeded")
	}
}
