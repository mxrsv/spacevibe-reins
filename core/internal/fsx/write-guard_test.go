package fsx

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/roots"
)

func armGuard(t *testing.T) {
	t.Helper()
	InstallWriteGuard(config.Config{Test: true})
	t.Cleanup(func() { SetWriteGuard(nil) })
}

// G-fix.2: with the guard armed, every write primitive refuses a path under the real home before
// touching anything, whichever spelling the caller used.
func TestEveryPrimitiveRefusesTheRealHome(t *testing.T) {
	real, err := roots.RealHome()
	if err != nil {
		t.Skip(err)
	}
	armGuard(t)
	scratch := tempDir(t)
	spellings := []string{filepath.Join(real, ".spacevibe-never-written", "x")}
	if dataVolume := "/System/Volumes/Data" + real; dirExists(dataVolume) {
		spellings = append(spellings, filepath.Join(dataVolume, ".spacevibe-never-written", "x"))
	}
	link := filepath.Join(scratch, "home-link")
	if os.Symlink(real, link) == nil {
		spellings = append(spellings, filepath.Join(link, ".spacevibe-never-written", "x"))
	}
	source := filepath.Join(scratch, "source")
	writeFile(t, source, "keep", 0o600)
	for _, bad := range spellings {
		ops := map[string]func() error{
			"AtomicWrite":         func() error { return AtomicWrite(bad, []byte("x"), 0o600, AtomicWriteOptions{}) },
			"CreateFileExclusive": func() error { return CreateFileExclusive(bad, []byte("x"), 0o600) },
			"RemoveFile":          func() error { return RemoveFile(bad) },
			"RemoveTree":          func() error { return RemoveTree(bad) },
			"Symlink":             func() error { return Symlink(source, bad) },
			"MkdirAll":            func() error { return MkdirAll(bad, 0o700) },
			"MkdirExclusive":      func() error { return MkdirExclusive(bad, 0o700) },
			"MoveWith to":         func() error { return MoveWith(source, bad, os.Rename) },
			"Move to":             func() error { return Move(source, bad) },
			"Move from":           func() error { return Move(bad, filepath.Join(scratch, "dest")) },
			"WithWriteLock":       func() error { return WithWriteLock(filepath.Dir(bad), func() error { return nil }) },
		}
		for name, op := range ops {
			e := wantStatus(t, op(), coreerr.StatusInternalFailure)
			if !strings.Contains(e.Message, "real home") {
				t.Errorf("%s(%q): %q", name, bad, e.Message)
			}
		}
		if _, err := os.Lstat(filepath.Join(real, ".spacevibe-never-written")); err == nil {
			t.Fatalf("a primitive created something under the real home (%q)", bad)
		}
	}
	if readFile(t, source) != "keep" {
		t.Error("the source was touched")
	}
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func TestGuardAllowsOrdinaryPaths(t *testing.T) {
	armGuard(t)
	dir := tempDir(t)
	if err := AtomicWrite(filepath.Join(dir, "a"), []byte("x"), 0o600, AtomicWriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := CreateFileExclusive(filepath.Join(dir, "b"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestNoGuardByDefaultAndSetClears(t *testing.T) {
	SetWriteGuard(nil)
	var seen []string
	SetWriteGuard(func(p string) error { seen = append(seen, p); return nil })
	t.Cleanup(func() { SetWriteGuard(nil) })
	dir := tempDir(t)
	if err := AtomicWrite(filepath.Join(dir, "a"), []byte("x"), 0o600, AtomicWriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if len(seen) != 1 || seen[0] != filepath.Join(dir, "a") {
		t.Fatalf("guard saw %v", seen)
	}
	SetWriteGuard(nil)
	seen = nil
	if err := AtomicWrite(filepath.Join(dir, "b"), []byte("x"), 0o600, AtomicWriteOptions{}); err != nil || len(seen) != 0 {
		t.Fatalf("cleared guard still called: %v %v", err, seen)
	}
	InstallWriteGuard(config.Config{}) // Test off: no guard
	if writeGuard.Load() != nil {
		t.Error("a guard was installed without SPACEVIBE_TEST")
	}
}

func TestGuardPlainErrorBecomesFixedSentence(t *testing.T) {
	SetWriteGuard(func(string) error { return os.ErrPermission })
	t.Cleanup(func() { SetWriteGuard(nil) })
	err := AtomicWrite(filepath.Join(tempDir(t), "a"), []byte("x"), 0o600, AtomicWriteOptions{})
	e := wantStatus(t, err, coreerr.StatusInternalFailure)
	if e.Message != "A write was refused by the write guard." {
		t.Error(e.Message)
	}
}
