package mutate

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/goldentest"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
	"spacevibe.dev/core/internal/usage"
)

const canary = "fixture-secret-do-not-show"

// copyHome is a private copy of the fixture HOME with the roots pointing at it (MutateTests.Copy).
type copyHome struct {
	tempHome
	r roots.Roots
}

func newCopy(t *testing.T) copyHome {
	t.Helper()
	base, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(base, "home")
	if err := goldentest.MaterializeInto(root); err != nil {
		t.Fatal(err)
	}
	h := tempHome{root, t}
	return copyHome{h, h.roots()}
}

// tokenTree is the home-token projection for a tree that holds json.Number: goldentest.HomeToken would turn a
// json.Number (a string kind) into a plain string, so numbers are carried over untouched here.
func tokenTree(v any, root string) any {
	switch x := v.(type) {
	case string:
		return goldentest.HomeTokenString(x, root)
	case []any:
		out := make([]any, len(x))
		for i, item := range x {
			out[i] = tokenTree(item, root)
		}
		return out
	case map[string]any:
		out := make(map[string]any, len(x))
		for k, item := range x {
			out[goldentest.HomeTokenString(k, root)] = tokenTree(item, root)
		}
		return out
	}
	return v
}

// sha1Text is sha1 of the text with the root replaced: String(decoding: bytes, as: UTF8.self), then replacing.
func sha1Text(data []byte, root string) string {
	return hashes.SHA1Hex([]byte(strings.ReplaceAll(textjs.Repair(string(data)), root, goldentest.Token)))
}

// measure is path -> sha1 of the text with the root replaced, "link:<target>" for a link (TreeHash.measure).
func (h copyHome) measure(dir string, skipTop ...string) map[string]string {
	h.t.Helper()
	out := map[string]string{}
	var visit func(folder, prefix string)
	visit = func(folder, prefix string) {
		entries, err := os.ReadDir(folder)
		if err != nil {
			h.t.Fatal(err)
		}
		for _, e := range entries { // ReadDir sorts by name
			rel := e.Name()
			if prefix != "" {
				rel = prefix + "/" + e.Name()
			}
			if prefix == "" && slices.Contains(skipTop, e.Name()) {
				continue
			}
			child := filepath.Join(folder, e.Name())
			info, err := os.Lstat(child)
			if err != nil {
				h.t.Fatal(err)
			}
			switch {
			case info.Mode()&os.ModeSymlink != 0:
				target, _ := os.Readlink(child)
				out[rel] = "link:" + strings.ReplaceAll(target, h.root, goldentest.Token)
			case info.IsDir():
				visit(child, rel)
			default:
				data, err := os.ReadFile(child)
				if err != nil {
					h.t.Fatal(err)
				}
				out[rel] = sha1Text(data, h.root)
			}
		}
	}
	visit(dir, "")
	return out
}

func (h copyHome) tree() map[string]string {
	return h.measure(h.root, ".reins", ".spacevibe", ".fixture-stamp")
}

// trash is what the trash holds, as sorted "<path inside the slot>:<sha1>".
func (h copyHome) trash() []string {
	out := []string{}
	for _, slot := range names(filepath.Join(h.data(), "trash")) {
		for k, v := range h.measure(filepath.Join(h.data(), "trash", slot)) {
			out = append(out, k+":"+v)
		}
	}
	sort.Strings(out)
	return out
}

func asAny(m map[string]string) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

// treeOf is an ojson value as the generic tree the canonical writer takes (numbers keep their text).
func treeOf(v ojson.Value) any {
	switch v.Kind() {
	case ojson.KindObject:
		members, _ := v.ObjectValue()
		out := make(map[string]any, len(members))
		for _, m := range members {
			out[m.Key] = treeOf(m.Value) // a duplicate key: the last one wins, as JSON.parse
		}
		return out
	case ojson.KindArray:
		items, _ := v.ArrayValue()
		out := make([]any, len(items))
		for i, item := range items {
			out[i] = treeOf(item)
		}
		return out
	case ojson.KindString:
		s, _ := v.StringValue()
		return s
	case ojson.KindNumber:
		n, _ := v.NumberText()
		return json.Number(n)
	case ojson.KindBool:
		b, _ := v.BoolValue()
		return b
	}
	return nil
}

func (h copyHome) parsedJSON(rel string) any {
	h.t.Helper()
	doc, err := ojson.Parse([]byte(h.read(rel)))
	if err != nil {
		h.t.Fatalf("%s is not JSON: %v", rel, err)
	}
	return tokenTree(treeOf(doc.Root()), h.root)
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func asMap(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}

func asString(v any) string {
	s, _ := v.(string)
	return s
}

func (h copyHome) applySetup(setup map[string]any) {
	h.t.Helper()
	if setup == nil {
		return
	}
	token := goldentest.Token
	if removes, ok := setup["remove"].([]any); ok {
		for _, rel := range removes {
			if err := os.RemoveAll(h.path(asString(rel))); err != nil {
				h.t.Fatal(err)
			}
		}
	}
	files := asMap(setup["files"])
	for _, rel := range sortedKeys(files) {
		h.write(rel, strings.ReplaceAll(asString(files[rel]), token, h.root))
	}
	links := asMap(setup["links"])
	for _, rel := range sortedKeys(links) {
		h.symlink(strings.ReplaceAll(asString(links[rel]), token, h.root), rel)
	}
}

func (h copyHome) itemID(find map[string]any) string {
	h.t.Helper()
	if id, ok := find["id"].(string); ok {
		return id
	}
	snap := inventory.Read(h.r)
	if find["kind"] == "hook" {
		for _, hook := range snap.Hooks {
			if string(hook.CLI) == find["cli"] && hook.Event == find["event"] && strings.Contains(hook.Command, asString(find["commandIncludes"])) {
				return hook.ID
			}
		}
		h.t.Fatalf("no hook for %v", find)
	}
	for _, item := range snap.Items {
		if string(item.Kind) == find["kind"] && string(item.CLI) == find["cli"] && item.Name == find["name"] {
			return item.ID
		}
	}
	h.t.Fatalf("no item for %v", find)
	return ""
}

// perform runs the operation the Node core ran (MutateTests.perform).
func (h copyHome) perform(op map[string]any) (Entry, error) {
	var clis []usage.CLI
	if list, ok := op["clis"].([]any); ok {
		for _, c := range list {
			clis = append(clis, usage.CLI(asString(c)))
		}
	}
	text := func(key string) string { return asString(op[key]) }
	switch op["fn"] {
	case "addSkill":
		return AddSkill(h.r, clis, text("name"), text("description"), text("body"))
	case "addAgent":
		return AddAgent(h.r, clis, text("name"), text("description"), text("instructions"))
	case "addHook":
		var matcher *string
		if m, ok := op["matcher"].(string); ok {
			matcher = &m
		}
		var timeout *float64
		if n, ok := op["timeout"].(json.Number); ok {
			f, _ := n.Float64()
			timeout = &f
		}
		return AddHook(h.r, clis, text("event"), matcher, strings.ReplaceAll(text("command"), goldentest.Token, h.root), timeout)
	case "removeItem":
		return RemoveItem(h.r, h.itemID(asMap(op["find"])))
	case "removeDeadHooks":
		return RemoveDeadHooks(h.r, usage.CLI(text("cli")))
	case "copyToOther":
		return CopyToOther(h.r, h.itemID(asMap(op["find"])))
	}
	h.t.Fatalf("test bug: unknown operation %v", op["fn"])
	return Entry{}, nil
}

// summary is the journal entry as the golden records it: label and ops without the keys that name trash paths or hold
// engine-only restore data.
func (h copyHome) summary(e Entry) any {
	dropped := []string{"to", "backup", "after", "restore"}
	ops := make([]any, len(e.Ops))
	for i, op := range e.Ops {
		members, _ := op.JSON.ObjectValue()
		kept := map[string]any{}
		for _, m := range members {
			if !slices.Contains(dropped, m.Key) {
				kept[m.Key] = treeOf(m.Value)
			}
		}
		ops[i] = kept
	}
	return tokenTree(map[string]any{"label": e.Label, "ops": ops}, h.root)
}

// bodyPretty is sha1 of the file with the final newline dropped (Node re-prints the whole file with one).
func (h copyHome) bodyPretty(rel string) string {
	text := strings.ReplaceAll(textjs.Repair(h.read(rel)), h.root, goldentest.Token)
	return hashes.SHA1Hex([]byte(strings.TrimSuffix(text, "\n")))
}

// projection normalizes one golden scenario to what is compared: name, error, journal, delta, json, body and trash.
// A body is compared only where Node's output was already pretty-printed (wasPretty): elsewhere Node re-prints the
// file and its bytes cannot match.
func scenarioWant(sc map[string]any) map[string]any {
	body := map[string]any{}
	for rel, v := range asMap(sc["body"]) {
		b := asMap(v)
		entry := map[string]any{"wasPretty": b["wasPretty"]}
		if b["wasPretty"] == true {
			entry["bodySha1"] = b["bodySha1"]
		}
		body[rel] = entry
	}
	trash, _ := sc["trash"].([]any)
	sorted := make([]any, len(trash))
	copy(sorted, trash)
	sort.Slice(sorted, func(i, j int) bool { return asString(sorted[i]) < asString(sorted[j]) })
	return map[string]any{
		"name": sc["name"], "error": sc["error"], "journal": sc["journal"], "delta": sc["delta"],
		"json": sc["json"], "body": body, "trash": sorted,
	}
}

func (h copyHome) runScenario(t *testing.T, sc map[string]any, hookFiles []any) map[string]any {
	t.Helper()
	name := asString(sc["name"])
	h.applySetup(asMap(sc["setup"]))
	before := h.tree()

	entry, err := h.perform(asMap(sc["op"]))
	after := h.tree()

	got := map[string]any{"name": name, "error": nil, "journal": nil}
	if err != nil {
		e, ok := coreerr.As(err)
		if !ok {
			t.Fatalf("%s: error %v is not a coreerr.Error", name, err)
		}
		got["error"] = map[string]any{"status": json.Number(itoa(e.Status)), "message": strings.ReplaceAll(e.Message, h.root, goldentest.Token)}
		if !maps_equal(before, after) {
			t.Errorf("%s: a refused operation must change nothing", name)
		}
	} else {
		got["journal"] = h.summary(entry)
	}

	// The files: same changed set; skills and agents byte for byte, the two hook files as parsed JSON.
	changed := map[string]any{}
	keys := map[string]bool{}
	for k := range before {
		keys[k] = true
	}
	for k := range after {
		keys[k] = true
	}
	for k := range keys {
		if before[k] == after[k] {
			continue
		}
		v, present := after[k]
		switch {
		case !present:
			changed[k] = nil
		case slices.Contains(hookFiles, any(k)):
			changed[k] = "json"
		default:
			changed[k] = v
		}
	}
	got["delta"] = changed

	jsonOut, bodyOut := map[string]any{}, map[string]any{}
	for rel, v := range asMap(sc["json"]) {
		_ = v
		jsonOut[rel] = h.parsedJSON(rel)
		pretty := asMap(asMap(sc["body"])[rel])["wasPretty"] == true
		b := map[string]any{"wasPretty": pretty}
		if pretty {
			b["bodySha1"] = h.bodyPretty(rel)
		}
		bodyOut[rel] = b
	}
	got["json"], got["body"] = jsonOut, bodyOut
	trash := h.trash()
	trashOut := make([]any, len(trash))
	for i, s := range trash {
		trashOut[i] = s
	}
	got["trash"] = trashOut

	// The journal never holds a secret from settings, whatever the operation did.
	journalText, _ := os.ReadFile(filepath.Join(h.data(), "journal.json"))
	if strings.Contains(string(journalText), canary) || err != nil && strings.Contains(err.Error(), canary) {
		t.Errorf("%s: the canary leaked", name)
	}

	// Undo: every byte of the tree comes back, and a second undo is refused.
	if err == nil {
		label, uerr := Undo(h.r, entry.ID)
		if uerr != nil || label != entry.Label {
			t.Errorf("%s: undo gave %q, %v", name, label, uerr)
		}
		if !maps_equal(h.tree(), before) {
			t.Errorf("%s: undo did not restore the tree", name)
		}
		_, second := Undo(h.r, entry.ID)
		if e, ok := coreerr.As(second); !ok || e.Status != 409 || e.Message != "This was already undone." {
			t.Errorf("%s: second undo gave %v", name, second)
		}
	}
	return got
}

func maps_equal(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if bv, ok := b[k]; !ok || bv != v {
			return false
		}
	}
	return true
}

// Swift: MutateTests.swift "the fixture copy hashes like the Node copy" and "an operation does what the Node core
// does, and undo puts every byte back" (37 scenarios).
// Projection mutate-tree: for the fixture copy path -> sha1 of the text with the root replaced, and per scenario the
// error or journal summary, the changed paths, the parsed hook files, the pretty bodies and the trash listing.
func TestGoldenMutate(t *testing.T) {
	golden, err := goldentest.LoadGolden("mutate")
	if err != nil {
		t.Fatal(err)
	}
	top := asMap(golden)
	scenarios, _ := top["scenarios"].([]any)
	hookFiles, _ := top["hookFiles"].([]any)
	goldentest.AssertCaseCount(t, "mutate scenarios", len(scenarios), 37)
	if len(hookFiles) == 0 {
		t.Fatal("golden has no hookFiles")
	}

	initial := newCopy(t)
	gotInitial := asAny(initial.tree())

	var want, got []any
	for _, raw := range scenarios {
		sc := asMap(raw)
		want = append(want, scenarioWant(sc))
		t.Run(asString(sc["name"]), func(t *testing.T) {
			h := newCopy(t)
			got = append(got, h.runScenario(t, sc, hookFiles))
		})
	}
	goldentest.AssertCanonicalEqual(t, "mutate-tree",
		map[string]any{"initial": top["initial"], "scenarios": want},
		map[string]any{"initial": gotInitial, "scenarios": got})
}
