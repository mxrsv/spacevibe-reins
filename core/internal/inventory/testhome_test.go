package inventory

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/usage"
)

// tempHome is a throwaway HOME. Its path has its symlinks resolved (macOS /var is a link). Tests never touch
// the real home: the roots come from here and SPACEVIBE_TEST=1 turns the guard on.
type tempHome struct {
	root string
	t    *testing.T
}

func newTempHome(t *testing.T) tempHome {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return tempHome{root, t}
}

func (h tempHome) path(rel string) string { return filepath.Join(h.root, rel) }
func (h tempHome) data() string           { return h.path(".spacevibe") }

func (h tempHome) cfg() config.Config {
	return config.Config{Test: true, UserHome: h.root, ClaudeConfigDir: h.path(".claude"), CodexHome: h.path(".codex"), Home: h.data()}
}

func (h tempHome) roots() roots.Roots {
	h.t.Helper()
	r, err := roots.Resolve(h.cfg(), h.t.TempDir())
	if err != nil {
		h.t.Fatal(err)
	}
	return r
}

func (h tempHome) write(rel string, content any) string {
	h.t.Helper()
	p := h.path(rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		h.t.Fatal(err)
	}
	var data []byte
	switch c := content.(type) {
	case string:
		data = []byte(c)
	case []byte:
		data = c
	}
	if err := os.WriteFile(p, data, 0o644); err != nil {
		h.t.Fatal(err)
	}
	return p
}

func (h tempHome) setModified(path, iso string) {
	h.t.Helper()
	at, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		h.t.Fatal(err)
	}
	if err := os.Chtimes(path, at, at); err != nil {
		h.t.Fatal(err)
	}
}

func skillFile(name string, description ...string) string {
	d := "d"
	if len(description) > 0 {
		d = description[0]
	}
	return "---\nname: " + name + "\ndescription: " + d + "\n---\n"
}

func hookConfig(event, command string, secret ...string) string {
	env := ""
	if len(secret) > 0 {
		env = `"env": {"API_TOKEN": "` + secret[0] + `"}, `
	}
	quoted, _ := json.Marshal(command)
	return `{` + env + `"hooks": {"` + event + `": [{"matcher": "Edit", "hooks": [{"type": "command", "command": ` + string(quoted) + `}]}]}}`
}

func mustTime(t testing.TB, iso string) time.Time {
	t.Helper()
	at, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		t.Fatal(err)
	}
	return at
}

func ptr[T any](v T) *T { return &v }

func item(inv Snapshot, name string, cli ...CLI) *Item {
	want := Claude
	if len(cli) > 0 {
		want = cli[0]
	}
	for i := range inv.Items {
		if inv.Items[i].Name == name && inv.Items[i].CLI == want {
			return &inv.Items[i]
		}
	}
	return nil
}

func itemByEntry(inv Snapshot, entry string) *Item {
	for i := range inv.Items {
		if inv.Items[i].Entry == entry {
			return &inv.Items[i]
		}
	}
	return nil
}

func hookByCommand(inv Snapshot, command string) *Hook {
	for i := range inv.Hooks {
		if inv.Hooks[i].Command == command {
			return &inv.Hooks[i]
		}
	}
	return nil
}

func scanOf(t *testing.T, r roots.Roots) usage.Result {
	t.Helper()
	res, err := usage.NewScanner(r).Scan(t.Context(), nil)
	if err != nil {
		t.Fatal(err)
	}
	return res
}

// jsonTree is v as the generic tree the canonical writer takes (numbers stay json.Number).
func jsonTree(t testing.TB, v any) any {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var out any
	if err := dec.Decode(&out); err != nil {
		t.Fatal(err)
	}
	return out
}

func hookHashOf(event, command string) string { return hashes.HookHash(event, command) }
