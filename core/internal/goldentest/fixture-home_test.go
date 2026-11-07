package goldentest

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/roots"
)

func requireDarwin(t *testing.T) {
	t.Helper()
	if runtime.GOOS != "darwin" {
		t.Skip("the canonical fixture root is a macOS path (B6)")
	}
}

func mustManifest(t *testing.T) Manifest {
	t.Helper()
	m, err := LoadManifest()
	if err != nil {
		t.Fatal(err)
	}
	return m
}

// Swift: FixtureHomeTests.swift "the manifest lists the tree, and every listed file is committed"
func TestFixtureManifestListsCommittedTree(t *testing.T) {
	m := mustManifest(t)
	fixtures, _ := FixturesDir()
	if m.Token != "$HOME" || len(m.Digest) != 64 {
		t.Fatalf("token %q digest length %d", m.Token, len(m.Digest))
	}
	AssertCaseCount(t, "manifest files", len(m.Mtimes), 200)
	for rel := range m.Mtimes {
		if _, err := os.Stat(filepath.Join(fixtures, "home", rel)); err != nil {
			t.Errorf("%s: %v", rel, err)
		}
	}
}

// Go addition: the digest in the manifest is the one make-golden.mjs computed over the committed home tree
// (sha256 of "rel\0text\0mtime\0" for each file, depth-first with names sorted), so the manifest and the tree
// cannot drift apart unnoticed.
func TestFixtureDigestMatchesCommittedTree(t *testing.T) {
	m := mustManifest(t)
	fixtures, _ := FixturesDir()
	h := sha256.New()
	count := 0
	var walk func(dir string)
	walk = func(dir string) {
		entries, err := os.ReadDir(filepath.Join(fixtures, "home", dir))
		if err != nil {
			t.Fatal(err)
		}
		sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
		for _, e := range entries {
			rel := filepath.Join(dir, e.Name())
			switch {
			case e.IsDir():
				walk(rel)
			case e.Type().IsRegular() && e.Name() != ".DS_Store":
				data, err := os.ReadFile(filepath.Join(fixtures, "home", rel))
				if err != nil {
					t.Fatal(err)
				}
				mtime, ok := m.Mtimes[rel]
				if !ok {
					t.Fatalf("%s is committed but not in the manifest", rel)
				}
				h.Write([]byte(rel + "\x00" + string(data) + "\x00" + strconv.FormatFloat(mtime, 'f', -1, 64) + "\x00"))
				count++
			}
		}
	}
	walk("")
	AssertCaseCount(t, "digested files", count, 200)
	if count != len(m.Mtimes) {
		t.Errorf("home tree has %d files, manifest lists %d", count, len(m.Mtimes))
	}
	if got := hex.EncodeToString(h.Sum(nil)); got != m.Digest {
		t.Errorf("digest of the committed tree is %s, manifest says %s", got, m.Digest)
	}
}

// Swift: FixtureHomeTests.swift "materialize builds the tree at the canonical path with paths and mtimes restored"
func TestFixtureMaterialize(t *testing.T) {
	requireDarwin(t)
	root, err := Materialize()
	if err != nil {
		t.Fatal(err)
	}
	if root != "/private/tmp/reins-fixture-home" {
		t.Fatalf("root %q", root)
	}
	m := mustManifest(t)
	settings, err := os.ReadFile(filepath.Join(root, ".claude/settings.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(settings), root+"/.claude/scripts/guard-destructive.sh") || strings.Contains(string(settings), "$HOME") {
		t.Error("settings.json does not hold the root path in place of $HOME")
	}
	for _, rel := range []string{".claude/scripts/guard-destructive.sh", ".reins"} {
		if _, err := os.Stat(filepath.Join(root, rel)); err != nil {
			t.Error(err)
		}
	}
	for _, rel := range []string{".claude/skills/ponytail/SKILL.md", ".claude/projects/-work-spacevibe-bench/session-000.jsonl"} {
		info, err := os.Stat(filepath.Join(root, rel))
		if err != nil {
			t.Fatal(err)
		}
		if got, want := info.ModTime().UnixMilli(), int64(m.Mtimes[rel]); got != want {
			t.Errorf("%s mtime %d, want %d", rel, got, want)
		}
	}
	if again, err := Materialize(); err != nil || again != root {
		t.Errorf("second call: %q, %v", again, err)
	}
	stamp, _ := os.ReadFile(filepath.Join(root, stampName))
	if string(stamp) != m.Digest {
		t.Errorf("stamp %q is not the manifest digest", stamp)
	}
}

// Go addition: the stamp alone is not trusted. checkTree on a private copy catches each way a tree can be stale
// while its stamp still matches, and tolerates what a scan writes into the data folder.
func TestFixtureTreeCheckCatchesCorruptionUnderMatchingStamp(t *testing.T) {
	fixtures, _ := FixturesDir()
	m := mustManifest(t)
	dest := filepath.Join(t.TempDir(), "copy")
	if err := MaterializeInto(dest); err != nil {
		t.Fatal(err)
	}
	files, err := expectedFiles(fixtures, m, dest)
	if err != nil {
		t.Fatal(err)
	}
	if p := checkTree(dest, m, files); len(p) != 0 {
		t.Fatalf("a fresh copy has problems: %v", p)
	}
	if err := os.WriteFile(filepath.Join(dest, ".reins/usage-cache.json"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if p := checkTree(dest, m, files); len(p) != 0 {
		t.Fatalf("a file in the data folder must be tolerated: %v", p)
	}

	cases := []struct {
		name    string
		corrupt func(t *testing.T)
		want    string
	}{
		{"one byte changed", func(t *testing.T) {
			path := filepath.Join(dest, ".claude/settings.json")
			data, _ := os.ReadFile(path)
			data[len(data)/2] ^= 1
			must(t, os.WriteFile(path, data, 0o644))
			must(t, os.Chtimes(path, mtimeOf(m.Mtimes[".claude/settings.json"]), mtimeOf(m.Mtimes[".claude/settings.json"])))
		}, "content differs: .claude/settings.json"},
		{"mtime moved", func(t *testing.T) {
			now := time.Now()
			must(t, os.Chtimes(filepath.Join(dest, ".claude/settings.json"), now, now))
		}, "mtime differs: .claude/settings.json"},
		{"extra file", func(t *testing.T) {
			must(t, os.WriteFile(filepath.Join(dest, ".claude/stray.txt"), nil, 0o644))
		}, "unexpected file: .claude/stray.txt"},
		{"missing file", func(t *testing.T) {
			must(t, os.Remove(filepath.Join(dest, ".claude/agents/architect.md")))
		}, "missing file: .claude/agents/architect.md"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			must(t, os.RemoveAll(dest))
			must(t, MaterializeInto(dest))
			c.corrupt(t)
			found := false
			for _, p := range checkTree(dest, m, files) {
				found = found || p == c.want
			}
			if !found {
				t.Errorf("want problem %q, got %v", c.want, checkTree(dest, m, files))
			}
		})
	}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

// Swift: FixtureHomeTests.swift "a private copy substitutes its own path and leaves no token"
func TestFixturePrivateCopy(t *testing.T) {
	copyDir := filepath.Join(t.TempDir(), "copy")
	must(t, MaterializeInto(copyDir))
	settings, err := os.ReadFile(filepath.Join(copyDir, ".claude/settings.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(settings), copyDir+"/.claude/scripts/notify-done.sh") || strings.Contains(string(settings), "$HOME") {
		t.Error("the copy does not hold its own path in place of $HOME")
	}
	if err := MaterializeInto(copyDir); err == nil {
		t.Error("a copy onto an existing folder must be refused")
	}
}

// Swift: FixtureHomeTests.swift "the fixture roots pass the real-home guard"
func TestFixtureRootsPassRealHomeGuard(t *testing.T) {
	env := Env(CanonicalRoot)
	cfg, err := config.LoadFrom(func(k string) string { return env[k] })
	if err != nil {
		t.Fatal(err)
	}
	realHome, err := roots.RealHome()
	if err != nil {
		t.Fatal(err)
	}
	r, err := roots.Resolve(cfg, realHome)
	if err != nil {
		t.Fatal(err)
	}
	if r.Claude.Root != "/private/tmp/reins-fixture-home/.claude" {
		t.Errorf("claude root %q", r.Claude.Root)
	}
}

// Swift: FixtureHomeTests.swift "inventory.json parses and describes the tree: items, hooks, usage input, filter counts"
func TestFixtureInventoryGoldenShape(t *testing.T) {
	golden, err := LoadGolden("inventory")
	if err != nil {
		t.Fatal(err)
	}
	top := golden.(map[string]any)
	inv := top["inventory"].(map[string]any)
	items, hooks := inv["items"].([]any), inv["hooks"].([]any)
	if len(items) <= 20 || len(hooks) != 9 {
		t.Errorf("items %d hooks %d", len(items), len(hooks))
	}
	if _, ok := top["usageInput"].(map[string]any)["totals"]; !ok {
		t.Error("usageInput.totals is missing")
	}
	if n := top["filterCounts"].(map[string]any)["dead"]; n.(interface{ String() string }).String() != "2" {
		t.Errorf("dead = %v", n)
	}
	if now, want := top["now"].(interface{ String() string }).String(), strconv.FormatFloat(mustManifest(t).Now, 'f', -1, 64); now != want {
		t.Errorf("now %s, manifest %s", now, want)
	}
	ids := make([]string, len(items))
	for i, it := range items {
		ids[i] = it.(map[string]any)["id"].(string)
	}
	if !sort.StringsAreSorted(ids) {
		t.Error("items are not sorted by id")
	}
}

// Swift: FixtureHomeTests.swift "every file the inventory golden names exists in the materialized tree, and no real path leaks"
func TestFixtureInventoryGoldenAgreesWithTree(t *testing.T) {
	requireDarwin(t)
	root, err := Materialize()
	if err != nil {
		t.Fatal(err)
	}
	golden, _ := LoadGolden("inventory")
	inv := golden.(map[string]any)["inventory"].(map[string]any)
	checked := 0
	for _, key := range []string{"items", "hooks"} {
		for _, row := range inv[key].([]any) {
			file := row.(map[string]any)["file"].(string)
			if !strings.HasPrefix(file, "$HOME/") {
				t.Errorf("%s does not start with $HOME/", file)
				continue
			}
			if _, err := os.Stat(strings.Replace(file, "$HOME", root, 1)); err != nil {
				t.Errorf("%s: %v", file, err)
			}
			checked++
		}
	}
	AssertCaseCount(t, "inventory rows with a file", checked, 31)
}

// Swift: FixtureHomeTests.swift "normalize and firstDifference behave as the later comparisons need"
func TestFixtureHomeTokenAndCanonicalDifference(t *testing.T) {
	actual := map[string]any{"p": "/private/tmp/reins-fixture-home/.claude", "n": []any{1, 2}, "o": map[string]any{"k": true},
		"/private/tmp/reins-fixture-home/x": "v"}
	normalized := HomeToken(actual, CanonicalRoot)
	want := map[string]any{"p": "$HOME/.claude", "n": []any{1, 2}, "o": map[string]any{"k": true}, "$HOME/x": "v"}
	AssertCanonicalEqual(t, "normalized", want, normalized)
	if actual["p"] != "/private/tmp/reins-fixture-home/.claude" {
		t.Error("HomeToken changed its input")
	}
	// A different number is a difference, and the diff names it.
	other := map[string]any{"p": "$HOME/.claude", "n": []any{1, 3}, "o": map[string]any{"k": true}, "$HOME/x": "v"}
	a, _ := Canonical(want)
	b, _ := Canonical(other)
	diff := UnifiedDiff("want", "got", string(a), string(b))
	if !strings.Contains(diff, "-    2\n+    3\n") {
		t.Errorf("diff does not show 2 -> 3:\n%s", diff)
	}
	// Typed containers are normalized too.
	typed := HomeToken(map[string][]string{CanonicalRoot: {CanonicalRoot + "/a"}}, CanonicalRoot)
	AssertCanonicalEqual(t, "typed", map[string]any{"$HOME": []any{"$HOME/a"}}, typed)
}

// Go addition: the rebuild path, on a temporary root so the shared tree is never touched.
func TestFixtureMaterializeRebuildsStaleAndCorruptTrees(t *testing.T) {
	root := filepath.Join(t.TempDir(), "home")
	m := mustManifest(t)
	if got, err := materializeAt(root); err != nil || got != root {
		t.Fatalf("first build: %q %v", got, err)
	}
	settings := filepath.Join(root, ".claude/settings.json")
	good, _ := os.ReadFile(settings)

	// Corrupt under a matching stamp: rebuilt.
	must(t, os.WriteFile(settings, []byte("{}"), 0o644))
	if _, err := materializeAt(root); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(settings); string(got) != string(good) {
		t.Error("a corrupt file under a matching stamp was not rebuilt")
	}
	// Stale stamp: rebuilt.
	must(t, os.WriteFile(filepath.Join(root, stampName), []byte("old"), 0o644))
	if _, err := materializeAt(root); err != nil {
		t.Fatal(err)
	}
	if stamp, _ := os.ReadFile(filepath.Join(root, stampName)); string(stamp) != m.Digest {
		t.Error("a stale stamp was not rebuilt")
	}
	// A right tree is left alone (same inode for a file that a rebuild would replace).
	before, _ := os.Stat(settings)
	if _, err := materializeAt(root); err != nil {
		t.Fatal(err)
	}
	if after, _ := os.Stat(settings); !os.SameFile(before, after) {
		t.Error("a right tree was rebuilt")
	}
	// No staging or aside folder is left behind.
	left, _ := os.ReadDir(filepath.Dir(root))
	if len(left) != 1 {
		t.Errorf("leftover entries beside the tree: %v", left)
	}
	// A symlink or a plain file at the root is refused, never followed or removed.
	target := t.TempDir()
	link := filepath.Join(t.TempDir(), "link")
	must(t, os.Symlink(target, link))
	if _, err := materializeAt(link); err == nil {
		t.Error("a symlink at the root must be refused")
	}
	if entries, _ := os.ReadDir(target); len(entries) != 0 {
		t.Error("the symlink target was written to")
	}
	file := filepath.Join(t.TempDir(), "file")
	must(t, os.WriteFile(file, []byte("x"), 0o644))
	if _, err := materializeAt(file); err == nil {
		t.Error("a file at the root must be refused")
	}
}
