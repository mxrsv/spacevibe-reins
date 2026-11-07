//go:build unix

package usage

import (
	"os"
	"syscall"
	"testing"
)

// Extra (G2.1): a cache path that is a FIFO is an empty cache, never waited on; a FIFO log is skipped.
func TestFIFOsAreNotRead(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/projects/p/s1.jsonl", attach("2026-10-01", map[string]any{"type": "hook_success", "hookEvent": "Stop", "command": "c"}))
	r := h.roots()
	if err := os.MkdirAll(r.Data, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := syscall.Mkfifo(CachePath(r.Data), 0o600); err != nil {
		t.Skip("no mkfifo here")
	}
	if len(loadCache(r.Data)) != 0 {
		t.Error("a FIFO cache was read")
	}
	if got := mustScan(t, NewScanner(r)); len(got.Totals.Claude.Hook) != 1 {
		t.Errorf("hooks = %+v", got.Totals.Claude.Hook)
	}
}
