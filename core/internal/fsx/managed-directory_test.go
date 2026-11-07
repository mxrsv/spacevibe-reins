package fsx

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/roots"
)

func testRoots(t *testing.T) (config.Config, roots.Roots) {
	t.Helper()
	home := tempDir(t)
	cfg := config.Config{
		Test: true, UserHome: home, Home: filepath.Join(home, ".spacevibe"),
		ClaudeConfigDir: filepath.Join(home, ".claude"), CodexHome: filepath.Join(home, ".codex"),
	}
	r, err := roots.Resolve(cfg, "/nonexistent-real-home")
	if err != nil {
		t.Fatal(err)
	}
	return cfg, r
}

// Swift: StatuslineSetup.managedDirectory (LimitsStatuslineTests.swift covers it through install)
func TestManagedDirectory(t *testing.T) {
	cfg, r := testRoots(t)
	got, err := ManagedDirectory(cfg, r, "bin")
	if err != nil || got != filepath.Join(r.Data, "bin") {
		t.Fatalf("missing folder is fine: %q, %v", got, err)
	}
	if err := os.MkdirAll(filepath.Join(r.Data, "bin"), 0o700); err != nil {
		t.Fatal(err)
	}
	if _, err := ManagedDirectory(cfg, r, "bin"); err != nil {
		t.Errorf("real directory: %v", err)
	}
}

func TestManagedDirectoryRefusesAFile(t *testing.T) {
	cfg, r := testRoots(t)
	writeFile(t, filepath.Join(r.Data, "bin"), "x", 0o600)
	_, err := ManagedDirectory(cfg, r, "bin")
	e := wantStatus(t, err, coreerr.StatusConflict)
	if e.Message != "The collector directory is not a regular directory." {
		t.Error(e.Message)
	}
}

func TestManagedDirectoryRefusesALinkOutOfTheDataFolder(t *testing.T) {
	skipOnWindows(t)
	cfg, r := testRoots(t)
	outside := filepath.Join(tempDir(t), "elsewhere")
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(r.Data, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(r.Data, "bin")); err != nil {
		t.Fatal(err)
	}
	_, err := ManagedDirectory(cfg, r, "bin")
	wantStatus(t, err, coreerr.StatusConflict)
}

// Swift: FileEditTests.swift "under SPACEVIBE_TEST=1 an edit refuses a path under the real home"
func TestManagedDirectoryRefusesUnderTheRealHome(t *testing.T) {
	cfg, r := testRoots(t)
	real, err := roots.RealHome()
	if err != nil {
		t.Skip(err)
	}
	r.Data = filepath.Join(real, ".spacevibe-never-written")
	_, err = ManagedDirectory(cfg, r, "bin")
	wantStatus(t, err, coreerr.StatusInternalFailure)
	if _, serr := os.Stat(r.Data); serr == nil {
		t.Error("the real-home folder was created")
	}
}

func TestModificationTime(t *testing.T) {
	file := filepath.Join(tempDir(t), "f")
	writeFile(t, file, "x", 0o600)
	want := time.Date(2026, 11, 7, 12, 0, 0, 123456789, time.UTC)
	if err := os.Chtimes(file, want, want); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(file)
	if err != nil {
		t.Fatal(err)
	}
	if got := ModificationTime(info); got.Unix() != want.Unix() {
		t.Errorf("got %v, want %v", got, want)
	}
}

// G-fix.20: the folder must be ours and closed to others.
func TestManagedDirectoryRefusesWorldOrGroupWritable(t *testing.T) {
	skipOnWindows(t)
	cfg, r := testRoots(t)
	folder := filepath.Join(r.Data, "bin")
	if err := os.MkdirAll(folder, 0o700); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []os.FileMode{0o770, 0o707, 0o777} {
		if err := os.Chmod(folder, mode); err != nil {
			t.Fatal(err)
		}
		_, err := ManagedDirectory(cfg, r, "bin")
		e := wantStatus(t, err, coreerr.StatusConflict)
		if e.Message != "The collector directory is not owned by you or can be written by others." {
			t.Error(e.Message)
		}
	}
	for _, mode := range []os.FileMode{0o700, 0o755, 0o750} {
		if err := os.Chmod(folder, mode); err != nil {
			t.Fatal(err)
		}
		if _, err := ManagedDirectory(cfg, r, "bin"); err != nil {
			t.Errorf("mode %v refused: %v", mode, err)
		}
	}
}

// A folder owned by somebody else is refused. Needs a folder we do not own: /var or /tmp roots are
// root-owned on unix, but the check works from a Lstat, so exercise ownedAndPrivate directly.
func TestOwnedAndPrivateRefusesForeignOwner(t *testing.T) {
	skipOnWindows(t)
	info, err := os.Lstat("/")
	if err != nil {
		t.Skip(err)
	}
	if os.Getuid() == 0 {
		t.Skip("root owns /")
	}
	if ownedAndPrivate(info) {
		t.Error("a root-owned folder counted as ours")
	}
}
