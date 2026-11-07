package statusline

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/roots"
)

// tempHome is a throwaway HOME with its links resolved (macOS /var is a link). Tests never touch the real home.
type tempHome struct {
	t    *testing.T
	root string
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
	return config.Config{Test: true, UserHome: h.root, CodexHome: h.path(".codex"), Home: h.path(".spacevibe"), ClaudeConfigDir: h.path(".claude")}
}

func (h tempHome) roots() roots.Roots {
	h.t.Helper()
	r, err := roots.Resolve(h.cfg(), h.t.TempDir())
	if err != nil {
		h.t.Fatal(err)
	}
	return r
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

func (h tempHome) text(rel string) string {
	h.t.Helper()
	data, err := os.ReadFile(h.path(rel))
	if err != nil {
		h.t.Fatal(err)
	}
	return string(data)
}

func (h tempHome) exists(rel string) bool {
	_, err := os.Lstat(h.path(rel))
	return err == nil
}

func (h tempHome) mode(rel string) os.FileMode {
	h.t.Helper()
	info, err := os.Stat(h.path(rel))
	if err != nil {
		h.t.Fatal(err)
	}
	return info.Mode().Perm()
}

// account writes the Claude state file with an account (LimitsStatuslineTests.account).
func (h tempHome) account(name string) {
	h.write(".claude/.claude.json", `{"oauthAccount":{"accountUuid":"`+name+`","organizationUuid":"synthetic-org"},
 "cachedUsageUtilization":{"fetchedAtMs":1793800000000,"utilization":{"limits":[
 {"kind":"weekly_all","group":"weekly","percent":62,"resets_at":"2026-11-06T16:00:00Z"}]}}}`)
}

const (
	statusNow = 1_793_900_000.0
	reset     = 1_794_000_000
)

func at(seconds float64) time.Time {
	whole := int64(seconds)
	return time.Unix(whole, int64((seconds-float64(whole))*1e9))
}
