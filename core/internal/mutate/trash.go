package mutate

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// The app's own trash under the data root (JournalTrash.swift). Removed files and the old bytes of edited files
// go here, never into the journal, so the journal stays small and never holds file content. Layout as in Node
// mutate: <data>/trash/<epoch ms>-<8 hex>/<name>, folders 0700.

// renameFile is the rename step of every move. A test replaces it with a function that fails with EXDEV to
// exercise the cross-volume copy (H13); nothing else touches it.
var renameFile = os.Rename

// moveFile moves from to to and fails instead of replacing. Across volumes fsx copies, fsyncs and removes the
// source (what FileManager.moveItem did silently).
func moveFile(from, to string) error { return fsx.MoveWith(from, to, renameFile) }

// pathExists is true when anything sits at the path, including a link whose target is gone.
func pathExists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

func trashDir(r roots.Roots) string { return filepath.Join(r.Data, "trash") }

func ensureDataFolders(r roots.Roots) error {
	if err := fsx.MkdirAll(trashDir(r), 0o700); err != nil {
		return fail("Could not create the SpaceVibe data folder "+r.Data+".", coreerr.StatusInternalFailure)
	}
	return nil
}

// slot makes a fresh trash folder and returns the path where name goes inside it.
func slot(r roots.Roots, name string) (string, error) {
	var b [4]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fail("Could not create the SpaceVibe trash folder.", coreerr.StatusInternalFailure)
	}
	folder := filepath.Join(trashDir(r), strconv.FormatInt(time.Now().UnixMilli(), 10)+"-"+hex.EncodeToString(b[:]))
	if err := fsx.MkdirAll(folder, 0o700); err != nil {
		return "", fail("Could not create the SpaceVibe trash folder.", coreerr.StatusInternalFailure)
	}
	return filepath.Join(folder, filepath.Base(name)), nil
}

// moveToTrash moves a file or folder into the trash. The returned moved op lets undo move it back.
func moveToTrash(r roots.Roots, path string) (Op, error) {
	destination, err := slot(r, path)
	if err != nil {
		return Op{}, err
	}
	if err := moveFile(path, destination); err != nil {
		return Op{}, err
	}
	return Moved(path, destination), nil
}

// removePath removes a link without touching what it points at (the link text is kept for undo); anything else
// goes to the trash.
func removePath(r roots.Roots, path string) (Op, error) {
	if target, err := os.Readlink(path); err == nil {
		if err := fsx.RemoveFile(path); err != nil {
			return Op{}, err
		}
		return LinkRemoved(path, target), nil
	}
	return moveToTrash(r, path)
}

// trashSlotPattern is the name of a folder this package makes: <epoch ms>-<8 hex>. The sweep touches nothing else.
var trashSlotPattern = regexp.MustCompile(`^([0-9]+)-[0-9a-f]{8}$`)

// slotOf is the name of the trash folder a path points into, or "" when the path is not strictly inside the trash.
// strict adds the containment rule of Undo (absolute, no ".." segment); the loose form is for "is this slot still
// referenced?", where a path Undo would refuse must still protect its slot.
func (c *containment) slotOf(p string, strict bool) string {
	if strict && !c.trashPath(p) {
		return ""
	}
	if !filepath.IsAbs(p) {
		return ""
	}
	clean := filepath.Clean(p)
	for _, candidate := range []string{clean, roots.ResolvedPath(clean)} {
		for _, folder := range c.trash {
			rel, err := filepath.Rel(folder, candidate)
			if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
				continue
			}
			return strings.SplitN(rel, string(filepath.Separator), 2)[0]
		}
	}
	return ""
}

// slotsOf collects the slots named by any string inside any op, whatever the op kind or the key, so ops of kinds
// this version cannot undo still keep their copies.
func (c *containment) slotsOf(entries []Entry, strict bool) map[string]bool {
	slots := map[string]bool{}
	var walk func(v ojson.Value)
	walk = func(v ojson.Value) {
		if s, ok := v.StringValue(); ok {
			if name := c.slotOf(s, strict); name != "" {
				slots[name] = true
			}
		}
		if items, ok := v.ArrayValue(); ok {
			for _, item := range items {
				walk(item)
			}
		}
		if members, ok := v.ObjectValue(); ok {
			for _, m := range members {
				walk(m.Value)
			}
		}
	}
	for _, e := range entries {
		for _, op := range e.Ops {
			walk(op.JSON)
		}
	}
	return slots
}

// pruneTrash ends the trash copies of the entries the journal just dropped, and sweeps the trash. It runs under the
// write lock, after the journal is written, with the entries that stay (kept) and the ones that went (cut).
//
//   - A slot named by a dropped entry goes unless a kept entry still names it.
//   - Sweep: a slot older than JournalMaxAge (by its name) that no kept entry names goes. This also clears the copies
//     of entries an older version dropped without deleting them.
//
// Every delete is a folder directly inside <data>/trash that passes the same containment check Undo uses, removed
// with fsx.RemoveTree; nothing outside the trash is ever removed. A failed delete is skipped, not reported: the
// change itself succeeded, and the next write tries again.
func pruneTrash(r roots.Roots, kept, cut []Entry, now time.Time) {
	guard := newContainment(r)
	referenced := guard.slotsOf(kept, false)
	doomed := map[string]bool{}
	for name := range guard.slotsOf(cut, true) {
		// Only a real folder this package made: a file, a link or a folder with any other name stays.
		if info, err := os.Lstat(filepath.Join(trashDir(r), name)); err == nil && info.IsDir() && trashSlotPattern.MatchString(name) {
			doomed[name] = true
		}
	}
	if items, err := os.ReadDir(trashDir(r)); err == nil {
		for _, item := range items {
			match := trashSlotPattern.FindStringSubmatch(item.Name())
			if match == nil || !item.IsDir() {
				continue
			}
			if ms, err := strconv.ParseInt(match[1], 10, 64); err == nil && now.Sub(time.UnixMilli(ms)) > JournalMaxAge {
				doomed[item.Name()] = true
			}
		}
	}
	for name := range doomed {
		path := filepath.Join(trashDir(r), name)
		if referenced[name] || filepath.Dir(path) != trashDir(r) || !guard.trashPath(path) {
			continue
		}
		_ = fsx.RemoveTree(path)
	}
}
