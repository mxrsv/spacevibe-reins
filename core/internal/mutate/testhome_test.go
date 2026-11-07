package mutate

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/roots"
)

// tempHome is a throwaway HOME. Its path has its links resolved (macOS /var is a link). Tests never touch the real
// home: the roots come from here and SPACEVIBE_TEST=1 plus the installed write guard refuse anything else.
type tempHome struct {
	root string
	t    *testing.T
}

func newHome(t *testing.T) tempHome {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return tempHome{root, t}
}

func (h tempHome) path(rel string) string { return filepath.Join(h.root, rel) }
func (h tempHome) claude() string         { return h.path(".claude") }
func (h tempHome) data() string           { return h.path(".spacevibe") }

func (h tempHome) roots() roots.Roots {
	h.t.Helper()
	r, err := roots.Resolve(homeConfig(h.root), h.t.TempDir())
	if err != nil {
		h.t.Fatal(err)
	}
	return r
}

// write creates a file with its folders (test setup may use os; only package code goes through fsx).
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

func (h tempHome) read(rel string) string {
	h.t.Helper()
	data, err := os.ReadFile(h.path(rel))
	if err != nil {
		h.t.Fatal(err)
	}
	return string(data)
}

func (h tempHome) symlink(target, rel string) string {
	h.t.Helper()
	p := h.path(rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		h.t.Fatal(err)
	}
	if err := os.Symlink(target, p); err != nil {
		h.t.Fatal(err)
	}
	return p
}

func (h tempHome) mode(p string) os.FileMode {
	h.t.Helper()
	info, err := os.Stat(p)
	if err != nil {
		h.t.Fatal(err)
	}
	return info.Mode().Perm()
}

func exists(p string) bool {
	_, err := os.Lstat(p)
	return err == nil
}

// strayTemp lists any .tmp file in the folders (every .tmp counts, not only SpaceVibe's own).
func strayTemp(folders ...string) []string {
	var out []string
	for _, f := range folders {
		entries, _ := os.ReadDir(f)
		for _, e := range entries {
			if strings.HasSuffix(e.Name(), ".tmp") {
				out = append(out, filepath.Join(f, e.Name()))
			}
		}
	}
	return out
}

func names(folder string) []string {
	entries, _ := os.ReadDir(folder)
	out := make([]string, len(entries))
	for i, e := range entries {
		out[i] = e.Name()
	}
	return out
}

// trashFiles lists "<slot>/<name>" for every file one level inside a trash slot.
func trashFiles(r roots.Roots) []string {
	var out []string
	for _, slot := range names(trashDir(r)) {
		for _, name := range names(filepath.Join(trashDir(r), slot)) {
			out = append(out, slot+"/"+name)
		}
	}
	return out
}

// wantErr asserts err is a coreerr.Error with the status, and returns its message.
func wantErr(t *testing.T, err error, status int) string {
	t.Helper()
	e, ok := coreerr.As(err)
	if !ok {
		t.Fatalf("error %v is not a coreerr.Error", err)
	}
	if e.Status != status {
		t.Fatalf("status %d (%q), want %d", e.Status, e.Message, status)
	}
	return e.Message
}

// must returns v, or panics (and so fails the test with the error) when err is not nil. It takes the pair a call
// returns, which a method with an extra *testing.T parameter could not.
func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

func historyOf(t *testing.T, r roots.Roots) []EntryRef {
	t.Helper()
	h, err := History(r)
	if err != nil {
		t.Fatal(err)
	}
	return h
}

func str(s string) *string { return &s }

// skillMd is a minimal SKILL.md.
func skillMd(name, description string) string {
	return "---\nname: " + name + "\ndescription: " + description + "\n---\n"
}

// jsonObject parses text as generic JSON for assertions.
func jsonObject(t *testing.T, text string) map[string]any {
	t.Helper()
	var out map[string]any
	if err := json.Unmarshal([]byte(text), &out); err != nil {
		t.Fatalf("not JSON: %v", err)
	}
	return out
}
