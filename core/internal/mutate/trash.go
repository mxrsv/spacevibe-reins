package mutate

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
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
		return fail("Could not create the Reins data folder "+r.Data+".", coreerr.StatusInternalFailure)
	}
	return nil
}

// slot makes a fresh trash folder and returns the path where name goes inside it.
func slot(r roots.Roots, name string) (string, error) {
	var b [4]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fail("Could not create the Reins trash folder.", coreerr.StatusInternalFailure)
	}
	folder := filepath.Join(trashDir(r), strconv.FormatInt(time.Now().UnixMilli(), 10)+"-"+hex.EncodeToString(b[:]))
	if err := fsx.MkdirAll(folder, 0o700); err != nil {
		return "", fail("Could not create the Reins trash folder.", coreerr.StatusInternalFailure)
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
