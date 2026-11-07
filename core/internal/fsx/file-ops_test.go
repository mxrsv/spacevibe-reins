package fsx

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
)

func TestCreateFileExclusive(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	path := filepath.Join(dir, "new.json")
	if err := CreateFileExclusive(path, []byte("one"), NewFileMode); err != nil {
		t.Fatal(err)
	}
	if readFile(t, path) != "one" || modeOf(t, path) != 0o600 {
		t.Errorf("content %q mode %v", readFile(t, path), modeOf(t, path))
	}
	wantStatus(t, CreateFileExclusive(path, []byte("two"), NewFileMode), coreerr.StatusConflict)
	if readFile(t, path) != "one" {
		t.Error("an existing file was overwritten")
	}
	// A link, even a dangling one, is never written through.
	link := filepath.Join(dir, "link")
	if err := os.Symlink(filepath.Join(dir, "nowhere"), link); err != nil {
		t.Fatal(err)
	}
	wantStatus(t, CreateFileExclusive(link, []byte("x"), NewFileMode), coreerr.StatusConflict)
	if _, err := os.Lstat(filepath.Join(dir, "nowhere")); err == nil {
		t.Error("wrote through a link")
	}
	// Missing folder: 500, nothing created.
	wantStatus(t, CreateFileExclusive(filepath.Join(dir, "no", "such", "f"), []byte("x"), NewFileMode), coreerr.StatusInternalFailure)
}

func TestRemoveFile(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	target := filepath.Join(dir, "target")
	writeFile(t, target, "keep", 0o600)
	link := filepath.Join(dir, "link")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if err := RemoveFile(link); err != nil {
		t.Fatal(err)
	}
	if readFile(t, target) != "keep" {
		t.Error("removing a link removed its target")
	}
	if err := RemoveFile(target); err != nil {
		t.Fatal(err)
	}
	wantStatus(t, RemoveFile(target), coreerr.StatusNotFound)
	folder := filepath.Join(dir, "folder")
	if err := os.Mkdir(folder, 0o700); err != nil {
		t.Fatal(err)
	}
	wantStatus(t, RemoveFile(folder), coreerr.StatusConflict)
}

func TestRemoveTree(t *testing.T) {
	dir := tempDir(t)
	writeFile(t, filepath.Join(dir, "b", "c", "f"), "x", 0o600)
	if err := RemoveTree(filepath.Join(dir, "b")); err != nil {
		t.Fatal(err)
	}
	if err := RemoveTree(filepath.Join(dir, "b")); err != nil {
		t.Errorf("missing path: %v", err)
	}
	wantStatus(t, RemoveTree("relative/dir"), coreerr.StatusForbidden)
	wantStatus(t, RemoveTree(string(filepath.Separator)), coreerr.StatusForbidden)
}

func TestSymlinkAndMkdirAll(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	link := filepath.Join(dir, "a", "link")
	if err := MkdirAll(filepath.Dir(link), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := Symlink("../relative-dangling", link); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.Readlink(link); got != "../relative-dangling" {
		t.Errorf("link text %q", got)
	}
	wantStatus(t, Symlink("x", link), coreerr.StatusConflict)
}

func TestMoveRenames(t *testing.T) {
	dir := tempDir(t)
	from, to := filepath.Join(dir, "from"), filepath.Join(dir, "trash", "to")
	writeFile(t, from, "payload", 0o640)
	if err := MkdirAll(filepath.Dir(to), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := Move(from, to); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(from); err == nil {
		t.Error("source remains")
	}
	if readFile(t, to) != "payload" {
		t.Error("content lost")
	}
}

func TestMoveRefusesToReplace(t *testing.T) {
	dir := tempDir(t)
	from, to := filepath.Join(dir, "from"), filepath.Join(dir, "to")
	writeFile(t, from, "new", 0o600)
	writeFile(t, to, "old", 0o600)
	wantStatus(t, Move(from, to), coreerr.StatusConflict)
	if readFile(t, to) != "old" || readFile(t, from) != "new" {
		t.Error("a refused move changed a file")
	}
}

// H13: a rename across volumes fails with EXDEV; Move then copies, fsyncs, and removes the source.
func TestMoveFallsBackOnCrossDevice(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	from, to := filepath.Join(dir, "skill"), filepath.Join(dir, "trash-item")
	writeFile(t, filepath.Join(from, "SKILL.md"), "body", 0o640)
	writeFile(t, filepath.Join(from, "sub", "deep.txt"), "deep", 0o600)
	if err := os.Symlink("SKILL.md", filepath.Join(from, "alias")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/outside/never-followed", filepath.Join(from, "dangling")); err != nil {
		t.Fatal(err)
	}
	var synced []string
	oldSync := syncDirFunc
	syncDirFunc = func(d string) error { synced = append(synced, d); return nil }
	t.Cleanup(func() { syncDirFunc = oldSync })
	exdev := func(string, string) error { return &os.LinkError{Op: "rename", Old: from, New: to, Err: syscall.EXDEV} }
	if err := moveWith(from, to, exdev); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(from); err == nil {
		t.Error("source remains after the copy fallback")
	}
	if readFile(t, filepath.Join(to, "SKILL.md")) != "body" || readFile(t, filepath.Join(to, "sub", "deep.txt")) != "deep" {
		t.Error("content differs")
	}
	if modeOf(t, filepath.Join(to, "SKILL.md")) != 0o640 {
		t.Errorf("mode %v", modeOf(t, filepath.Join(to, "SKILL.md")))
	}
	if got, _ := os.Readlink(filepath.Join(to, "alias")); got != "SKILL.md" {
		t.Errorf("link copied as %q", got)
	}
	if got, _ := os.Readlink(filepath.Join(to, "dangling")); got != "/outside/never-followed" {
		t.Errorf("dangling link copied as %q", got)
	}
	if len(synced) == 0 {
		t.Error("no folder was fsynced")
	}
}

func TestMoveOtherRenameErrorIs500(t *testing.T) {
	dir := tempDir(t)
	from, to := filepath.Join(dir, "from"), filepath.Join(dir, "to")
	writeFile(t, from, "x", 0o600)
	boom := func(string, string) error { return errors.New("boom " + canary) }
	e := wantStatus(t, moveWith(from, to, boom), coreerr.StatusInternalFailure)
	if !strings.HasPrefix(e.Message, "Could not move ") {
		t.Error(e.Message)
	}
}

// G-fix.20: the folder is fsynced after the rename, in AtomicWrite and in Move.
func TestFolderFsyncedAfterRename(t *testing.T) {
	var synced []string
	oldSync := syncDirFunc
	syncDirFunc = func(d string) error { synced = append(synced, d); return nil }
	t.Cleanup(func() { syncDirFunc = oldSync })
	dir := tempDir(t)
	path := filepath.Join(dir, "f")
	if err := AtomicWrite(path, []byte("x"), 0o600, AtomicWriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if len(synced) != 1 || synced[0] != dir {
		t.Fatalf("AtomicWrite synced %v", synced)
	}
	synced = nil
	if err := Move(path, filepath.Join(dir, "g")); err != nil {
		t.Fatal(err)
	}
	if len(synced) == 0 || synced[0] != dir {
		t.Fatalf("Move synced %v", synced)
	}
	synced = nil
	// A failed write does not claim durability.
	err := AtomicWrite(filepath.Join(dir, "h"), []byte("x"), 0o600, AtomicWriteOptions{BeforeRename: func() error { return errors.New("stop") }})
	if err == nil || len(synced) != 0 {
		t.Fatalf("err %v synced %v", err, synced)
	}
	// The real fsync on a real folder works, and a missing folder is just an error value.
	if err := syncDirectory(dir); err != nil {
		t.Errorf("real folder fsync: %v", err)
	}
	if err := syncDirectory(filepath.Join(dir, "missing")); err == nil {
		t.Error("fsync of a missing folder reported success")
	}
}
