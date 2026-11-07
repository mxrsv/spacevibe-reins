package mutate

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"spacevibe.dev/core/internal/inventory"
)

// exdev fails every rename like a move across volumes does.
func exdev(from, to string) error {
	return &os.LinkError{Op: "rename", Old: from, New: to, Err: syscall.EXDEV}
}

// H13: FileManager.moveItem copied across volumes; os.Rename returns EXDEV. With the rename failing that way, a removal
// still lands in the trash (copied, then the source removed) and Undo still brings it back, byte for byte, links included.
func TestTrashMoveAcrossVolumes(t *testing.T) {
	old := renameFile
	renameFile = exdev
	defer func() { renameFile = old }()

	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/packed/SKILL.md", skillMd("packed", "has extras"))
	h.write(".claude/skills/packed/scripts/run.sh", "#!/bin/sh\nexit 0\n")
	if err := os.Chmod(h.path(".claude/skills/packed/scripts/run.sh"), 0o755); err != nil {
		t.Fatal(err)
	}
	h.symlink("SKILL.md", ".claude/skills/packed/alias.md")
	var id string
	for _, it := range inventory.Read(r).Items {
		if it.Name == "packed" {
			id = it.ID
		}
	}
	entry := must(RemoveItem(r, id))
	to, _ := entry.Ops[0].str("to")
	if entry.Ops[0].Type() != "moved" || exists(h.path(".claude/skills/packed")) {
		t.Fatalf("op %q, source still there", entry.Ops[0].Type())
	}
	if data, _ := os.ReadFile(filepath.Join(to, "scripts/run.sh")); string(data) != "#!/bin/sh\nexit 0\n" {
		t.Errorf("trashed script %q", data)
	}
	if target, err := os.Readlink(filepath.Join(to, "alias.md")); err != nil || target != "SKILL.md" {
		t.Errorf("trashed link %q, %v", target, err)
	}

	must(Undo(r, entry.ID))
	if h.read(".claude/skills/packed/SKILL.md") != skillMd("packed", "has extras") || h.mode(h.path(".claude/skills/packed/scripts/run.sh")) != 0o755 {
		t.Error("undo did not restore the skill")
	}
	if target, _ := os.Readlink(h.path(".claude/skills/packed/alias.md")); target != "SKILL.md" {
		t.Errorf("restored link %q", target)
	}
}

// A rename that fails for any other reason is a 500 and leaves the source where it is.
func TestTrashMoveOtherFailureLeavesSource(t *testing.T) {
	old := renameFile
	renameFile = func(string, string) error { return errors.New("boom") }
	defer func() { renameFile = old }()

	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/keep/SKILL.md", skillMd("keep", "d"))
	var id string
	for _, it := range inventory.Read(r).Items {
		if it.Name == "keep" {
			id = it.ID
		}
	}
	_, err := RemoveItem(r, id)
	wantErr(t, err, 500)
	if !exists(h.path(".claude/skills/keep/SKILL.md")) || len(historyOf(t, r)) != 0 {
		t.Error("the source moved or an entry was recorded")
	}
}
