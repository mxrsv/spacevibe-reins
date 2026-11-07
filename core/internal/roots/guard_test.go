package roots

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
)

func mustRealHome(t *testing.T) string {
	t.Helper()
	real, err := RealHome()
	if err != nil || real == "" {
		t.Fatalf("RealHome = %q, %v", real, err)
	}
	return real
}

func wantRefused(t *testing.T, err error) {
	t.Helper()
	e, ok := coreerr.As(err)
	if !ok || e.Status != coreerr.StatusInternalFailure || !strings.Contains(e.Message, "real home") {
		t.Fatalf("want a 500 coreerr naming the real home, got %v", err)
	}
}

// Swift: FileEditTests.swift "under SPACEVIBE_TEST=1 an edit refuses a path under the real home"
// (the guard, FileEdit.refuseRealHomeUnderTest). WriteGuardTests.swift has no real-home case.
func TestRefusesPathUnderRealHome(t *testing.T) {
	real := mustRealHome(t)
	target := filepath.Join(real, ".spacevibe-never-written", "settings.json")
	wantRefused(t, RefuseRealHomeUnderTest(config.Config{Test: true}, target))
	wantRefused(t, RefuseRealHomeUnderTest(config.Config{Test: true}, real)) // the home itself
	if _, err := os.Lstat(target); err == nil {
		t.Fatal("the guard test must not create anything under the real home")
	}
}

func TestGuardLeavesOtherPathsAlone(t *testing.T) {
	real := mustRealHome(t)
	tmp := newTempHome(t)
	if err := RefuseRealHomeUnderTest(config.Config{Test: true}, tmp.url("a/b.json")); err != nil {
		t.Errorf("temp path refused: %v", err)
	}
	// A sibling that shares the real home's name prefix is not under it.
	if err := RefuseRealHomeUnderTest(config.Config{Test: true}, real+"-other/x"); err != nil {
		t.Errorf("sibling refused: %v", err)
	}
	// Without SPACEVIBE_TEST nothing is checked.
	if err := RefuseRealHomeUnderTest(config.Config{}, filepath.Join(real, "x")); err != nil {
		t.Errorf("guard active without the flag: %v", err)
	}
}

func TestGuardFollowsSymlinkIntoRealHome(t *testing.T) {
	real := mustRealHome(t)
	scratch := newTempHome(t)
	link := scratch.url("innocent")
	if err := os.Symlink(real, link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	wantRefused(t, RefuseRealHomeUnderTest(config.Config{Test: true}, filepath.Join(link, "not", "created", "yet")))
}

// AC3 / H1: a test that overrides HOME must not hide the real home. RealHome reads the password
// database, so the guard stays armed. On darwin this must also hold with CGO_ENABLED=0.
func TestGuardSurvivesHomeOverride(t *testing.T) {
	before := mustRealHome(t)
	fake := newTempHome(t).root
	t.Setenv("HOME", fake)
	t.Setenv("USERPROFILE", fake)
	after := mustRealHome(t)
	if after != before {
		t.Fatalf("RealHome followed $HOME: %q before, %q after the override", before, after)
	}
	if after == fake {
		t.Fatalf("RealHome returned the overridden HOME %q", fake)
	}
	wantRefused(t, RefuseRealHomeUnderTest(config.Config{Test: true}, filepath.Join(after, ".claude", "settings.json")))
	// Resolve fed the account's home (as the caller does) still refuses a HOME that points at it.
	_, err := Resolve(config.Config{Test: true, UserHome: after}, after)
	underRealHome(t, err)
}

// H4: a different spelling of the real home on a case-insensitive volume is still the real home.
func TestGuardIgnoresCaseOnCaseInsensitiveVolume(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("macOS volumes are case-insensitive by default; elsewhere case differs for real")
	}
	real := mustRealHome(t)
	swapped := strings.ToUpper(real)
	if swapped == real {
		t.Skip("home has no letters to change")
	}
	if _, err := os.Stat(swapped); err != nil {
		t.Skip("volume is case-sensitive")
	}
	wantRefused(t, RefuseRealHomeUnderTest(config.Config{Test: true}, filepath.Join(swapped, ".claude", "x")))
	_, err := Resolve(config.Config{Test: true, ClaudeConfigDir: filepath.Join(swapped, ".claude")}, real)
	underRealHome(t, err)
}
