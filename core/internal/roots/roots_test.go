package roots

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"spacevibe.dev/core/internal/config"
)

// tempHome is a throwaway folder whose path has its symlinks resolved (macOS /var is a link), so
// path comparisons are stable.
type tempHome struct{ root string }

func newTempHome(t *testing.T) tempHome {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return tempHome{root}
}

func (h tempHome) claude() string { return filepath.Join(h.root, ".claude") }
func (h tempHome) codex() string  { return filepath.Join(h.root, ".codex") }
func (h tempHome) data() string   { return filepath.Join(h.root, ".spacevibe") }
func (h tempHome) url(rel string) string {
	return filepath.Join(h.root, rel)
}

// cfg points every root at this folder, with the real-home guard on.
func (h tempHome) cfg() config.Config {
	return config.Config{Test: true, UserHome: h.root, ClaudeConfigDir: h.claude(), CodexHome: h.codex(), Home: h.data()}
}

func underRealHome(t *testing.T, err error) *UnderRealHomeError {
	t.Helper()
	var e *UnderRealHomeError
	if !errors.As(err, &e) {
		t.Fatalf("want *UnderRealHomeError, got %v", err)
	}
	return e
}

// Swift: RootsTests.swift "accepts temp roots and derives the CLI folders"
func TestAcceptsTempRoots(t *testing.T) {
	fakeReal, scratch := newTempHome(t), newTempHome(t)
	r, err := Resolve(scratch.cfg(), fakeReal.root)
	if err != nil {
		t.Fatal(err)
	}
	checks := []struct{ name, got, want string }{
		{"claude root", r.Claude.Root, scratch.claude()},
		{"claude hook file", r.Claude.HookFile, filepath.Join(scratch.claude(), "settings.json")},
		{"claude logs", filepath.Base(r.Claude.Logs), "projects"},
		{"codex hook file", filepath.Base(r.Codex.HookFile), "hooks.json"},
		{"codex logs", filepath.Base(r.Codex.Logs), "sessions"},
		{"codex skills", filepath.Base(r.Codex.Skills), "skills"},
		{"claude agents", filepath.Base(r.Claude.Agents), "agents"},
		{"data", r.Data, scratch.data()},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("%s = %q, want %q", c.name, c.got, c.want)
		}
	}
}

// Swift: RootsTests.swift "Claude Code's state file follows CLAUDE_CONFIG_DIR, else sits in HOME; Gemini CLI's folder is in HOME"
func TestStateFileAndGemini(t *testing.T) {
	fakeReal, scratch := newTempHome(t), newTempHome(t)
	configured, err := Resolve(scratch.cfg(), fakeReal.root)
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(scratch.claude(), ".claude.json"); configured.ClaudeState != want {
		t.Errorf("claudeState = %q, want %q", configured.ClaudeState, want)
	}
	if want := scratch.url(".gemini"); configured.Gemini != want {
		t.Errorf("gemini = %q, want %q", configured.Gemini, want)
	}
	cfg := scratch.cfg()
	cfg.ClaudeConfigDir = ""
	got, err := Resolve(cfg, fakeReal.root)
	if err != nil {
		t.Fatal(err)
	}
	if want := scratch.url(".claude.json"); got.ClaudeState != want {
		t.Errorf("claudeState without CLAUDE_CONFIG_DIR = %q, want %q", got.ClaudeState, want)
	}
}

// Swift: RootsTests.swift "falls back to folders under HOME and ignores empty values"
func TestDefaults(t *testing.T) {
	fakeReal, scratch := newTempHome(t), newTempHome(t)
	cfg := config.Config{Test: true, UserHome: scratch.root, ClaudeConfigDir: ""}
	r, err := Resolve(cfg, fakeReal.root)
	if err != nil {
		t.Fatal(err)
	}
	if r.Claude.Root != scratch.claude() || r.Codex.Root != scratch.codex() || r.Data != scratch.data() {
		t.Fatalf("defaults = %q %q %q", r.Claude.Root, r.Codex.Root, r.Data)
	}
}

// With HOME unset, the real home is the fallback (Swift: `value("HOME") ?? realHome`).
func TestHomeFallsBackToRealHome(t *testing.T) {
	r, err := Resolve(config.Config{}, "/real/me")
	if err != nil {
		t.Fatal(err)
	}
	if r.Claude.Root != "/real/me/.claude" || r.Data != "/real/me/.spacevibe" || r.Gemini != "/real/me/.gemini" {
		t.Fatalf("got %+v", r)
	}
}

// Swift: RootsTests.swift "SPACEVIBE_TEST=1 refuses a root under the real home"
func TestRefusesRealRoots(t *testing.T) {
	fakeReal, scratch := newTempHome(t), newTempHome(t)
	deep := filepath.Join(fakeReal.root, "deep", "dir")
	for _, key := range []string{"CLAUDE_CONFIG_DIR", "CODEX_HOME", "SPACEVIBE_HOME"} {
		cfg := scratch.cfg()
		switch key {
		case "CLAUDE_CONFIG_DIR":
			cfg.ClaudeConfigDir = deep
		case "CODEX_HOME":
			cfg.CodexHome = deep
		default:
			cfg.Home = deep
		}
		if _, err := Resolve(cfg, fakeReal.root); err == nil {
			t.Errorf("%s under the real home was accepted", key)
		} else {
			underRealHome(t, err)
		}
	}
	// HOME itself being the real home means all three defaults are real.
	cfg := scratch.cfg()
	cfg.ClaudeConfigDir, cfg.CodexHome, cfg.Home = "", "", ""
	cfg.UserHome = fakeReal.root
	if _, err := Resolve(cfg, fakeReal.root); err == nil {
		t.Error("HOME = real home was accepted")
	} else {
		underRealHome(t, err)
	}
}

// Swift: RootsTests.swift "the error names the root and the label"
func TestErrorDetails(t *testing.T) {
	fakeReal, scratch := newTempHome(t), newTempHome(t)
	cfg := scratch.cfg()
	cfg.CodexHome = filepath.Join(fakeReal.root, ".codex")
	_, err := Resolve(cfg, fakeReal.root)
	e := underRealHome(t, err)
	if e.Label != "codex" || e.Path != cfg.CodexHome {
		t.Fatalf("got %+v", e)
	}
	want := "SPACEVIBE_TEST=1: the codex root " + cfg.CodexHome + " is under the real home. Point HOME, CLAUDE_CONFIG_DIR, CODEX_HOME and SPACEVIBE_HOME at a temporary folder."
	if err.Error() != want {
		t.Fatalf("message = %q", err.Error())
	}
}

// Swift: RootsTests.swift "a symlink that leads into the real home is refused, even for a root that does not exist yet"
func TestRefusesThroughSymlinks(t *testing.T) {
	fakeReal, scratch := newTempHome(t), newTempHome(t)
	if err := os.MkdirAll(fakeReal.claude(), 0o755); err != nil {
		t.Fatal(err)
	}
	link := scratch.url("innocent")
	if err := os.Symlink(fakeReal.claude(), link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	for _, dir := range []string{link, filepath.Join(link, "not", "created", "yet")} {
		cfg := scratch.cfg()
		cfg.ClaudeConfigDir = dir
		_, err := Resolve(cfg, fakeReal.root)
		underRealHome(t, err)
	}
}

// Swift: RootsTests.swift "a symlinked home is compared by its real path"
func TestRealHomeBehindSymlink(t *testing.T) {
	fakeReal, scratch := newTempHome(t), newTempHome(t)
	alias := scratch.url("home-alias")
	if err := os.Symlink(fakeReal.root, alias); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	cfg := scratch.cfg()
	cfg.ClaudeConfigDir = fakeReal.claude()
	_, err := Resolve(cfg, alias)
	underRealHome(t, err)
}

// Swift: RootsTests.swift "a sibling folder whose name starts like the real home is not under it"
func TestPrefixIsNotAncestor(t *testing.T) {
	scratch := newTempHome(t)
	cfg := scratch.cfg()
	cfg.ClaudeConfigDir = scratch.url("me-other/.claude")
	if _, err := Resolve(cfg, scratch.url("me")); err != nil {
		t.Fatal(err)
	}
}

// Swift: RootsTests.swift "without SPACEVIBE_TEST nothing is checked"
func TestNoGuardWithoutFlag(t *testing.T) {
	fakeReal, scratch := newTempHome(t), newTempHome(t)
	cfg := scratch.cfg()
	cfg.Test = false // unset and "0" both load as false (config.LoadFrom)
	cfg.ClaudeConfigDir = fakeReal.claude()
	r, err := Resolve(cfg, fakeReal.root)
	if err != nil || r.Claude.Root != fakeReal.claude() {
		t.Fatalf("got %+v, %v", r.Claude, err)
	}
}

// Swift: RootsTests.swift "the account's real home, as the password database says, is refused"
func TestTheActualRealHome(t *testing.T) {
	real, err := RealHome()
	if err != nil || real == "" {
		t.Fatalf("RealHome = %q, %v", real, err)
	}
	// Pure path resolution: nothing is read or written under the real home.
	_, err = Resolve(config.Config{Test: true, UserHome: real}, real)
	underRealHome(t, err)
	// And a temp home is never the real home.
	if _, err := Resolve(newTempHome(t).cfg(), real); err != nil {
		t.Fatal(err)
	}
}

// Roots.swift keeps every root as given: resolvedPath is used only inside the real-home guard, never on
// the returned URLs. Checked by compiling Roots.swift: HOME=/tmp/x gives /tmp/x/.claude, not
// /private/tmp/x/.claude. A symlinked HOME must stay as the link the caller passed.
func TestResolveKeepsSymlinkedHomeAsGiven(t *testing.T) {
	h := newTempHome(t)
	target := h.url("target")
	if err := os.Mkdir(target, 0o755); err != nil {
		t.Fatal(err)
	}
	link := h.url("link")
	if err := os.Symlink(target, link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	r, err := Resolve(config.Config{Test: true, UserHome: link}, "/real/me")
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"claude": filepath.Join(link, ".claude"), "data": filepath.Join(link, ".spacevibe"),
		"state": filepath.Join(link, ".claude.json"), "gemini": filepath.Join(link, ".gemini"),
	}
	got := map[string]string{"claude": r.Claude.Root, "data": r.Data, "state": r.ClaudeState, "gemini": r.Gemini}
	for k, w := range want {
		if got[k] != w {
			t.Errorf("%s = %q, want %q", k, got[k], w)
		}
	}
}
