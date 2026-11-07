package rules

import (
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/goldentest"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// RulesGoldenTests.swift: the Go rules against the frozen golden/rules.json, projection "rules-view" (plan "Parity
// method"): ruleObject, gridObject, the preview outcome, {ok}|{error:{status,message}}, the parsed .json files after
// each write (the data folder excluded) and the Codex flag view. Both sides go through goldentest.Canonical and must be
// equal as bytes. Reads run on the shared fixture HOME and on rules-home/main; every write case runs on a fresh copy of
// rules-home/main in a temp home.

type obj = map[string]any

func asObj(v any) obj { m, _ := v.(obj); return m }
func asList(v any) []any {
	l, _ := v.([]any)
	return l
}
func asStr(v any) string { s, _ := v.(string); return s }

// tokenTree is the home-token projection for a tree that holds json.Number (goldentest.HomeToken would turn one into
// a plain string).
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
	case obj:
		out := make(obj, len(x))
		for k, item := range x {
			out[goldentest.HomeTokenString(k, root)] = tokenTree(item, root)
		}
		return out
	}
	return v
}

func orNull[T any](p *T) any {
	if p == nil {
		return nil
	}
	return *p
}

// goldenView turns Go results into the JSON shape of the frozen goldens and replays its cases.
type goldenView struct {
	t     *testing.T
	store *Store
	root  string
}

func scopeFrom(root, kind, rel string) Scope {
	dir := ""
	if rel != "" {
		dir = join(root, rel)
	}
	switch kind {
	case "project":
		return ProjectScope(dir)
	case "local":
		return LocalScope(dir)
	}
	return Global
}

func scopeFromKey(root, key string) Scope {
	kind, rel, _ := strings.Cut(key, ":")
	return scopeFrom(root, kind, rel)
}

func ruleObject(x Rule) obj {
	var dir any
	if x.Dir != nil {
		dir = *x.Dir
	}
	return obj{"id": x.ID, "scope": string(x.Scope), "dir": dir, "file": x.File, "verdict": string(x.Verdict), "rule": x.Rule,
		"tool": orNull(x.Tool), "specifier": orNull(x.Specifier)}
}

func gridObject(cells []Cell) []any {
	out := []any{}
	for _, c := range cells {
		ids := []any{}
		for _, r := range c.Rules {
			ids = append(ids, r.ID)
		}
		out = append(out, obj{"capability": string(c.Capability), "label": c.Label, "state": string(c.State), "editable": c.Editable, "rules": ids})
	}
	return out
}

func pairs(list []VerdictRule) []any {
	out := []any{}
	for _, p := range list {
		out = append(out, obj{"verdict": string(p.Verdict), "rule": p.Rule})
	}
	return out
}

// outcome is {ok: value} or {error: {status, message}}, like attempt in the golden script.
func outcome(body func() (any, error)) obj {
	v, err := body()
	if err == nil {
		return obj{"ok": v}
	}
	if e, ok := coreerr.As(err); ok {
		return obj{"error": obj{"status": e.Status, "message": e.Message}}
	}
	return obj{"error": obj{"status": -1, "message": err.Error()}}
}

func (v goldenView) previewOutcome(scope Scope, c Capability, verdict Verdict) obj {
	return outcome(func() (any, error) {
		p, err := v.store.PreviewSetCapability(scope, c, verdict)
		if err != nil {
			return nil, err
		}
		return obj{"capability": string(p.Capability), "verdict": string(p.Verdict), "scopeLabel": p.ScopeLabel, "current": string(p.Current),
			"resulting": string(p.Resulting), "replaces": pairs(p.Replaces), "writes": pairs(p.Writes)}, nil
	})
}

func (v goldenView) list(scope Scope) Listing {
	v.t.Helper()
	l, err := v.store.ListRules(scope)
	if err != nil {
		v.t.Fatalf("list %v: %v", scope, err)
	}
	return l
}

// reads is the "lists, grids, merged, previews, codex" part of one section, in the golden's shape. The keys come from
// the golden, as in Swift.
func (v goldenView) reads(expected obj) (obj, int) {
	v.t.Helper()
	lists, grids, merged, previews := asObj(expected["lists"]), obj{}, obj{}, obj{}
	keys := make([]string, 0, len(lists))
	for k := range lists {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	gotLists := obj{}
	for _, key := range keys {
		scope := scopeFromKey(v.root, key)
		listing := v.list(scope)
		rules := []any{}
		for _, r := range listing.Rules {
			rules = append(rules, ruleObject(r))
		}
		problems := []any{}
		for _, p := range listing.Problems {
			problems = append(problems, p)
		}
		gotLists[key] = obj{"rules": rules, "problems": problems}
		grids[key] = gridObject(CapabilityGrid(listing.Rules))
		for _, c := range Capabilities {
			for _, verdict := range Verdicts {
				previews[key+"|"+string(c)+"|"+string(verdict)] = v.previewOutcome(scope, c, verdict)
			}
		}
	}
	mergedKeys := make([]string, 0)
	for k := range asObj(expected["merged"]) {
		mergedKeys = append(mergedKeys, k)
	}
	sort.Strings(mergedKeys)
	for _, rel := range mergedKeys {
		listing, err := v.store.ListRules(ScopesFor(join(v.root, rel))...)
		if err != nil {
			v.t.Fatalf("merged %s: %v", rel, err)
		}
		merged[rel] = gridObject(CapabilityGrid(listing.Rules))
	}
	return obj{"lists": gotLists, "grids": grids, "merged": merged, "previews": previews, "codex": codexView(ReadCodexPermissions(v.store.roots))}, len(previews)
}

// codexView is the Codex flag view of the golden (snake_case keys, flags as an object, numbers as doubles).
func codexView(c CodexPermissions) obj {
	flags := func(list []Flag) obj {
		out := obj{}
		for _, f := range list {
			switch x := f.Value.(type) {
			case json.Number:
				n, _ := strconv.ParseFloat(string(x), 64)
				out[f.Key] = n
			default:
				out[f.Key] = x
			}
		}
		return out
	}
	var policy any
	if c.ApprovalPolicy != nil {
		if c.ApprovalPolicy.IsGranular {
			policy = obj{"granular": flags(c.ApprovalPolicy.Granular)}
		} else {
			policy = c.ApprovalPolicy.Mode
		}
	}
	var workspace any
	if w := c.SandboxWorkspaceWrite; w != nil {
		roots := []any{}
		for _, r := range w.WritableRoots {
			roots = append(roots, r)
		}
		workspace = obj{"network_access": orNull(w.NetworkAccess), "writable_roots": roots}
	}
	warnings := []any{}
	for _, w := range c.Warnings {
		warnings = append(warnings, w)
	}
	profiles := []any{}
	for _, p := range c.Profiles {
		profiles = append(profiles, obj{"name": p.Name, "filesystemEntries": p.FilesystemEntries, "networkEntries": p.NetworkEntries, "networkFlags": flags(p.NetworkFlags)})
	}
	projects := []any{}
	for _, p := range c.Projects {
		projects = append(projects, obj{"path": p.Path, "trust_level": orNull(p.TrustLevel)})
	}
	return obj{
		"present": c.Present, "model": string(c.Model), "unrestricted": c.Unrestricted, "warnings": warnings,
		"approval_policy": policy, "sandbox_mode": orNull(c.SandboxMode), "sandbox_workspace_write": workspace,
		"default_permissions": orNull(c.DefaultPermissions), "approvals_reviewer": orNull(c.ApprovalsReviewer),
		"profiles": profiles, "projects": projects,
		"rules": obj{"files": c.Rules.Files, "allow": c.Rules.Allow, "prompt": c.Rules.Prompt, "forbidden": c.Rules.Forbidden, "other": c.Rules.Other},
	}
}

// materialize copies rules-home/<name> into dest, with $HOME replaced by dest (Fixtures/rules-home/<name>).
func materialize(t *testing.T, name, dest string) {
	t.Helper()
	dir, err := goldentest.FixturesDir()
	if err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(dir, "rules-home", name)
	err = filepath.WalkDir(source, func(path string, d fs.DirEntry, err error) error {
		if err != nil || !d.Type().IsRegular() {
			return err
		}
		rel, _ := filepath.Rel(source, path)
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		target := filepath.Join(dest, rel)
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		return os.WriteFile(target, []byte(strings.ReplaceAll(string(data), goldentest.Token, dest)), 0o644)
	})
	if err != nil {
		t.Fatal(err)
	}
}

// numberTree is an ojson value as the generic tree the canonical writer takes (numbers keep their text).
func numberTree(v ojson.Value) any {
	switch v.Kind() {
	case ojson.KindObject:
		members, _ := v.ObjectValue()
		out := make(obj, len(members))
		for _, m := range members {
			out[m.Key] = numberTree(m.Value) // a duplicate key: the last one wins, as JSON.parse
		}
		return out
	case ojson.KindArray:
		items, _ := v.ArrayValue()
		out := make([]any, len(items))
		for i, item := range items {
			out[i] = numberTree(item)
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

// settingsAfter is every .json file of the home, parsed; a file that is not JSON is recorded as a sentinel, never as
// its text.
func settingsAfter(t *testing.T, root string) obj {
	t.Helper()
	out := obj{}
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || filepath.Ext(path) != ".json" {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		if strings.HasPrefix(rel, ".reins") || strings.HasPrefix(rel, ".spacevibe") {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if doc, err := ojson.Parse(data); err == nil {
			out[rel] = numberTree(doc.Root())
		} else {
			out[rel] = "<not JSON>"
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

// runWrite replays one write case on the store and returns {ok|error, files}.
func (v goldenView) runWrite(item obj) obj {
	v.t.Helper()
	spec := asObj(item["scope"])
	scope := scopeFrom(v.root, asStr(spec["kind"]), asStr(spec["rel"]))
	args := asObj(item["args"])
	verdict := func(key string) Verdict { return Verdict(asStr(args[key])) }
	result := outcome(func() (any, error) {
		var entry *mutate.Entry
		switch asStr(item["fn"]) {
		case "addRule":
			e, err := v.store.AddRule(scope, verdict("verdict"), asStr(args["rule"]))
			if err != nil {
				return nil, err
			}
			entry = &e
		case "removeRule":
			e, err := v.store.RemoveRule(scope, verdict("verdict"), asStr(args["rule"]))
			if err != nil {
				return nil, err
			}
			entry = &e
		case "changeVerdict":
			e, err := v.store.ChangeVerdict(scope, asStr(args["rule"]), verdict("from"), verdict("to"))
			if err != nil {
				return nil, err
			}
			entry = &e
		case "setCapability":
			e, err := v.store.SetCapability(scope, Capability(asStr(args["capability"])), verdict("verdict"))
			if err != nil {
				return nil, err
			}
			entry = e
		default:
			v.t.Fatalf("test bug: unknown write %v", item["fn"])
		}
		if entry == nil {
			return nil, nil
		}
		ops := []any{}
		for _, op := range entry.Ops {
			existed := false
			if e, ok := op.JSON.Member("existed"); ok {
				existed, _ = e.BoolValue()
			}
			ops = append(ops, obj{"type": op.Type(), "existed": existed})
		}
		return obj{"label": entry.Label, "ops": ops}, nil
	})
	result["files"] = settingsAfter(v.t, v.root)
	return result
}

func newView(t *testing.T, r roots.Roots, root string) goldenView {
	return goldenView{t: t, store: NewStore(r, nil), root: root}
}

func resolveRoots(t *testing.T, cfg config.Config) roots.Roots {
	t.Helper()
	realHome, err := roots.RealHome()
	if err != nil {
		t.Fatal(err)
	}
	r, err := roots.Resolve(cfg, realHome)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func loadRulesGolden(t *testing.T) obj {
	t.Helper()
	g, err := goldentest.LoadGolden("rules")
	if err != nil {
		t.Fatal(err)
	}
	return asObj(g)
}

// sectionWant is the golden section restricted to the parts the Swift test compares.
func sectionWant(section obj) obj {
	return obj{"lists": section["lists"], "grids": section["grids"], "merged": section["merged"], "previews": section["previews"], "codex": section["codex"]}
}

func TestGoldenRules(t *testing.T) {
	golden := loadRulesGolden(t)
	want, got := obj{}, obj{}

	// shared fixture HOME: rules, grids, previews and Codex keys (RulesGoldenTests "goldenSharedHome").
	root, err := goldentest.Materialize()
	if err != nil {
		t.Fatal(err)
	}
	env := goldentest.Env(root)
	env["SPACEVIBE_HOME"] = t.TempDir() // the data folder never lands in the shared tree
	cfg, err := config.LoadFrom(func(k string) string { return env[k] })
	if err != nil {
		t.Fatal(err)
	}
	shared := newView(t, resolveRoots(t, cfg), root)
	sharedGot, sharedPreviews := shared.reads(asObj(golden["shared"]))
	got["shared"], want["shared"] = tokenTree(sharedGot, root), sectionWant(asObj(golden["shared"]))
	if n := len(asObj(asObj(golden["shared"])["lists"])); n == 0 || sharedPreviews != n*len(Capabilities)*len(Verdicts) {
		t.Errorf("shared: %d previews for %d lists", sharedPreviews, n)
	}
	global := CapabilityGrid(shared.list(Global).Rules)
	for c, state := range map[Capability]State{Read: StateAllow, Edit: StateMixed, Push: StateAsk} {
		if cellOf(global, c).State != state {
			t.Errorf("fixture global %s is %s, want %s: the fixture must keep covering a mixed cell, an own-rules cell and Read(*)", c, cellOf(global, c).State, state)
		}
	}

	// section fixture HOME (rules-home/main): the same reads, including broken, null and empty projects.
	home := newHome(t)
	materialize(t, "main", home.root)
	main := newView(t, home.roots(), home.root)
	mainGot, mainPreviews := main.reads(asObj(golden["main"]))
	got["main"], want["main"] = tokenTree(mainGot, home.root), sectionWant(asObj(golden["main"]))
	if n := len(asObj(asObj(golden["main"])["lists"])); n == 0 || mainPreviews != n*len(Capabilities)*len(Verdicts) {
		t.Errorf("main: %d previews for %d lists", mainPreviews, n)
	}
	if n := len(main.list(ProjectScope(join(home.root, "proj-broken"))).Problems); n != 1 {
		t.Errorf("proj-broken has %d problems, want 1", n)
	}
	goldentest.AssertCaseCount(t, "shared previews", sharedPreviews, 126)
	goldentest.AssertCaseCount(t, "main previews", mainPreviews, 162)

	// Codex configs of rules-home (RulesGoldenTests "goldenCodex").
	cases := asObj(golden["codex"])
	if len(cases) != 5 {
		t.Fatalf("%d Codex cases, want 5", len(cases))
	}
	codexGot, codexWant := obj{}, obj{}
	for name, expected := range cases {
		h := newHome(t)
		if name != "missing" {
			materialize(t, "codex-"+name, h.root)
		}
		codexGot[name] = tokenTree(codexView(ReadCodexPermissions(h.roots())), h.root)
		codexWant[name] = expected
	}
	got["codex"], want["codex"] = codexGot, codexWant

	// every write case gives the same settings, label and refusal (RulesGoldenTests "goldenWrites").
	writes := asList(golden["writes"])
	goldentest.AssertCaseCount(t, "writes", len(writes), 101)
	if len(writes) <= 100 {
		t.Fatalf("%d write cases, want more than 100", len(writes))
	}
	refused, noOps := 0, 0
	writesGot, writesWant := []any{}, []any{}
	for _, raw := range writes {
		item := asObj(raw)
		h := newHome(t)
		materialize(t, "main", h.root)
		view := newView(t, h.roots(), h.root)
		actual := view.runWrite(item)
		if actual["error"] != nil {
			refused++
		}
		if v, ok := actual["ok"]; ok && v == nil {
			noOps++
		}
		writesGot = append(writesGot, tokenTree(actual, h.root))
		writesWant = append(writesWant, item["expected"])
	}
	if refused <= 20 || noOps < 1 {
		t.Errorf("the golden keeps covering refusals (%d) and a no-op (%d)", refused, noOps)
	}
	t.Logf("writes: %d cases, %d refusals, %d no-ops", len(writes), refused, noOps)
	got["writes"], want["writes"] = writesGot, writesWant

	goldentest.AssertCanonicalEqual(t, "rules-view", want, got)
}
