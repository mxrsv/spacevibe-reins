package limits

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/roots"
)

// tempHome is a throwaway HOME. Its path has symlinks resolved (macOS /var is a link). Tests never touch the
// real home: every root comes from here and Test=true turns the real-home guard on.
type tempHome struct {
	t           *testing.T
	root        string
	unsetClaude bool
}

func newTempHome(t *testing.T) tempHome {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return tempHome{t: t, root: root}
}

func (h tempHome) path(rel string) string { return filepath.Join(h.root, rel) }

func (h tempHome) cfg() config.Config {
	c := config.Config{Test: true, UserHome: h.root, CodexHome: h.path(".codex"), Home: h.path(".spacevibe")}
	if !h.unsetClaude {
		c.ClaudeConfigDir = h.path(".claude")
	}
	return c
}

func (h tempHome) roots() roots.Roots {
	h.t.Helper()
	r, err := roots.Resolve(h.cfg(), h.t.TempDir())
	if err != nil {
		h.t.Fatal(err)
	}
	return r
}

func (h tempHome) mkdir(rel string) {
	h.t.Helper()
	if err := os.MkdirAll(h.path(rel), 0o755); err != nil {
		h.t.Fatal(err)
	}
}

func (h tempHome) write(rel, content string) string {
	h.t.Helper()
	p := h.path(rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		h.t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		h.t.Fatal(err)
	}
	return p
}

// setModified sets the modification time to seconds since 1970 (fractions allowed).
func setModified(t *testing.T, path string, seconds float64) {
	t.Helper()
	whole := int64(seconds)
	at := time.Unix(whole, int64((seconds-float64(whole))*1e9))
	if err := os.Chtimes(path, at, at); err != nil {
		t.Fatal(err)
	}
}

// read runs limits.Read at the given instant (seconds since 1970).
func (h tempHome) read(now float64) Result {
	h.t.Helper()
	whole := int64(now)
	result, err := Read(h.t.Context(), h.cfg(), h.roots(), time.Unix(whole, int64((now-float64(whole))*1e9)))
	if err != nil {
		h.t.Fatal(err)
	}
	return result
}

// accountKeyFor is the key the collector derives for account and organization in this home.
func (h tempHome) accountKeyFor(account, organization string) string {
	return hashes.SHA256Hex([]byte(h.roots().Claude.Root + "\n" + account + "\n" + organization))
}
