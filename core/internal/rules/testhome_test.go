package rules

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// canary stands in for a secret value: it must never show up in a result, a message, a label or the journal.
const canary = "canary-secret-9f3a1c"

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

func (h tempHome) mode(p string) os.FileMode {
	h.t.Helper()
	info, err := os.Stat(p)
	if err != nil {
		h.t.Fatal(err)
	}
	return info.Mode().Perm()
}

// project makes a folder with a .claude folder, listed in Codex config.toml so discovery finds it (RulesTests Sandbox).
func (h tempHome) project(name string) string {
	h.t.Helper()
	dir := h.path(name)
	if err := os.MkdirAll(filepath.Join(dir, ".claude"), 0o755); err != nil {
		h.t.Fatal(err)
	}
	old, _ := os.ReadFile(h.path(".codex/config.toml"))
	h.write(".codex/config.toml", string(old)+"[projects.\""+dir+"\"]\ntrust_level = \"trusted\"\n")
	return dir
}

// journal is the text of the journal, "" when there is none.
func (h tempHome) journal() string {
	data, _ := os.ReadFile(filepath.Join(h.data(), "journal.json"))
	return string(data)
}

// strayTemp lists any .tmp file in the folders.
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

func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

func historyOf(t *testing.T, r roots.Roots) []mutate.EntryRef {
	t.Helper()
	h, err := mutate.History(r)
	if err != nil {
		t.Fatal(err)
	}
	return h
}

// parsedRoot parses a settings file; the root value of the document.
func parsedRoot(t *testing.T, path string) ojson.Value {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	doc, err := ojson.Parse(data)
	if err != nil {
		t.Fatalf("%s is not JSON: %v", path, err)
	}
	return doc.Root()
}

// permissionList is the strings of settings.permissions.<verdict>, and whether the list exists.
func permissionList(t *testing.T, path string, verdict Verdict) ([]string, bool) {
	t.Helper()
	permissions, ok := parsedRoot(t, path).Member("permissions")
	if !ok {
		return nil, false
	}
	list, ok := permissions.Member(string(verdict))
	if !ok {
		return nil, false
	}
	items, _ := list.ArrayValue()
	out := make([]string, 0, len(items))
	for _, item := range items {
		if s, ok := item.StringValue(); ok {
			out = append(out, s)
		}
	}
	return out, true
}
