//go:build unix

package mutate

import (
	"path/filepath"
	"syscall"
	"testing"

	"spacevibe.dev/core/internal/inventory"
)

// G-fix.5: a skill that holds a FIFO is refused instead of hanging on it.
func TestCopyRefusesAFifo(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/pipe/SKILL.md", skillMd("pipe", "d"))
	if err := syscall.Mkfifo(h.path(".claude/skills/pipe/events"), 0o600); err != nil {
		t.Skip("no mkfifo:", err)
	}
	_, err := CopyToOther(r, idOf(t, r, "pipe", inventory.KindSkill, inventory.Claude))
	wantErr(t, err, 409)
	if exists(filepath.Join(r.Codex.Skills, "pipe")) {
		t.Error("the refused copy wrote something")
	}
	// An agent file swapped for a FIFO after the listing is not read (the open does not block and the descriptor is checked).
	h.write(".claude/agents/other.md", "x")
	if err := syscall.Mkfifo(h.path(".claude/agents/fifo.md"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err = locked(r, func(tx *Tx) (Entry, error) {
		return tx.copyItem(inventory.Item{Name: "fifo", Kind: inventory.KindAgent, CLI: inventory.Claude, Path: h.path(".claude/agents/fifo.md")})
	})
	wantErr(t, err, 409)
}
