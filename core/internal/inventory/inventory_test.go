package inventory

import (
	"encoding/json"
	"os"
	"reflect"
	"slices"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/usage"
)

// Swift: InventoryTests.swift "sha is the first 12 hex digits of SHA-1 (known vector)" and "bare drops the
// plugin prefix" (the functions live in internal/hashes; this pins the vectors where they are used).
func TestShaAndBare(t *testing.T) {
	for in, want := range map[string]string{"abc": "a9993e364706", "": "da39a3ee5e6b", strings.Repeat("a", 1000): "291e9a6c6699"} {
		if got := hashes.Sha(in); got != want {
			t.Errorf("Sha(%.5q) = %q, want %q", in, got, want)
		}
	}
	if hashes.Bare("neon:neon-postgres") != "neon-postgres" || hashes.Bare("plain") != "plain" {
		t.Error("Bare")
	}
}

// Swift: InventoryTests.swift "scriptPaths finds quoted and bare absolute script paths and nothing else"
func TestScriptPaths(t *testing.T) {
	for command, want := range map[string][]string{
		"sh '/a/b/c.sh'":                           {"/a/b/c.sh"},
		"node \"/x/y.mjs\" --flag":                 {"/x/y.mjs"},
		"/usr/bin/env python3 /opt/t/run.py":       {"/opt/t/run.py"},
		"echo hi":                                  {},
		"cat /etc/hosts":                           {},
		"sh /a.sh && sh /a.sh; sh /b.bash":         {"/a.sh", "/b.bash"},
		"sh \"$HOME/x.sh\"":                        {},
		"sh /nbsp.sh":                              {"/nbsp.sh"}, // ICU's \s counts U+00A0; so does this port
		"sh\v/vt.sh":                               {"/vt.sh"},
		"echo a;/semi.sh":                          {},
		"sh '/with space/x.py' \"/q/y.rb\"":        {"/with space/x.py", "/q/y.rb"},
		"sh /a/b.sh)/c/d.ts":                       {"/a/b.sh"},
		"/lead.zsh trailing":                       {"/lead.zsh"},
		"sh /not-a-script.txt '/also.cjs' /x.mjs;": {"/also.cjs", "/x.mjs"},
	} {
		if got := ScriptPaths(command); !reflect.DeepEqual(got, want) {
			t.Errorf("ScriptPaths(%q) = %q, want %q", command, got, want)
		}
	}
}

// Swift: InventoryTests.swift "skills and agents of both CLIs: names, owners, symlinks, system folders, plugins"
func TestItemsAndOwners(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/skills/glob/SKILL.md", skillFile("glob", "global skill"))
	h.write(".claude/skills/.hidden/SKILL.md", skillFile("hidden"))
	h.write(".claude/skills/_internal/SKILL.md", skillFile("internal"))
	h.write(".claude/skills/not-a-skill/README.md", "x")
	h.write(".claude/skills/noname/SKILL.md", "no frontmatter at all")
	h.write(".claude/agents/rev.md", "---\nname: rev\ndescription: reviews\n---\n")
	h.write(".claude/agents/notes.txt", "x")
	h.write(".codex/agents/helper.toml", "name = \"helper\"\ndescription = 'a toml agent'\ndeveloper_instructions = \"\"\"\nbody\n\"\"\"\n")
	h.write(".codex/skills/glob/SKILL.md", skillFile("glob"))
	// A symlinked skill folder.
	h.write("elsewhere/linked/SKILL.md", skillFile("linked"))
	if err := os.Symlink(h.path("elsewhere/linked"), h.path(".claude/skills/linked")); err != nil {
		t.Fatal(err)
	}
	// An enabled plugin with a skill, an agent and a hook.
	plugin := h.path("plugins-cache/acme")
	h.write("plugins-cache/acme/skills/acme-skill/SKILL.md", skillFile("acme-skill"))
	h.write("plugins-cache/acme/agents/acme-agent.md", "---\nname: acme-agent\n---\n")
	h.write("plugins-cache/acme/hooks/hooks.json", hookConfig("Stop", "echo plugin-hook"))
	h.write(".claude/plugins/installed_plugins.json", `{"plugins": {"acme@market": [{"installPath": "`+plugin+`"}], "off@market": [{"installPath": "`+plugin+`"}]}}`)
	h.write(".claude/settings.json", `{"enabledPlugins": {"acme@market": true, "off@market": false}}`)

	inv := Read(h.roots())
	if it := item(inv, "glob"); it == nil || it.Description != "global skill" || it.Owner != "user" || !it.Removable || !it.InOther {
		t.Errorf("glob = %+v", it)
	}
	if it := item(inv, "glob", Codex); it == nil || !it.InOther {
		t.Errorf("codex glob = %+v", it)
	}
	if item(inv, "hidden") != nil || item(inv, "internal") != nil || item(inv, "not-a-skill") != nil {
		t.Error("a system folder or a folder without SKILL.md became an item")
	}
	if it := itemByEntry(inv, "noname"); it == nil || it.Name != "noname" {
		t.Errorf("name falls back to the folder name: %+v", it)
	}
	if it := item(inv, "linked"); it == nil || it.Owner != "link" {
		t.Errorf("linked = %+v", it)
	}
	if it := item(inv, "rev"); it == nil || it.Kind != KindAgent {
		t.Errorf("rev = %+v", it)
	}
	if itemByEntry(inv, "notes.txt") != nil {
		t.Error("notes.txt became an item")
	}
	helper := item(inv, "helper", Codex)
	if helper == nil || helper.Description != "a toml agent" || helper.ID != "codex:agent:local:helper.toml" {
		t.Errorf("helper = %+v", helper)
	}
	// Plugins are read-only.
	if it := item(inv, "acme-skill"); it == nil || it.Owner != "acme" || it.Removable || it.ID != "claude:skill:acme:acme-skill" {
		t.Errorf("acme-skill = %+v", it)
	}
	if it := item(inv, "acme-agent"); it == nil || it.Removable {
		t.Errorf("acme-agent = %+v", it)
	}
	hook := hookByCommand(inv, "echo plugin-hook")
	if hook == nil || hook.Owner != "acme" || hook.Removable {
		t.Errorf("plugin hook = %+v", hook)
	}
	for _, it := range inv.Items {
		if it.Owner == "off" {
			t.Errorf("a disabled plugin's item is listed: %+v", it)
		}
	}
	if len(inv.Problems) != 0 {
		t.Errorf("problems = %q", inv.Problems)
	}
}

// Swift: InventoryTests.swift "skillOverrides reach global Claude skills only"
func TestOverrides(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/skills/a/SKILL.md", skillFile("a"))
	h.write(".claude/skills/b/SKILL.md", skillFile("b"))
	h.write(".codex/skills/a/SKILL.md", skillFile("a"))
	h.write(".claude/settings.json", `{"skillOverrides": {"a": "off"}}`)
	inv := Read(h.roots())
	claudeA, claudeB, codexA := item(inv, "a", Claude), item(inv, "b", Claude), item(inv, "a", Codex)
	if claudeA.SkillOverride == nil || *claudeA.SkillOverride != "off" || !claudeA.HasSkillOverride {
		t.Errorf("claude a = %+v", claudeA)
	}
	if claudeB.SkillOverride != nil || !claudeB.HasSkillOverride {
		t.Errorf("claude b = %+v", claudeB)
	}
	if codexA.HasSkillOverride {
		t.Errorf("codex a = %+v", codexA)
	}
	encode := func(i *Item) map[string]any {
		data, err := json.Marshal(i)
		if err != nil {
			t.Fatal(err)
		}
		var m map[string]any
		if err := json.Unmarshal(data, &m); err != nil {
			t.Fatal(err)
		}
		return m
	}
	if _, has := encode(codexA)["override"]; has {
		t.Error("the codex item writes an override member")
	}
	if v, has := encode(claudeB)["override"]; !has || v != nil {
		t.Errorf("claude b override = %v, %v; want present and null", v, has)
	}
	if v := encode(claudeA)["override"]; v != "off" {
		t.Errorf("claude a override = %v", v)
	}
}

// Swift: InventoryTests.swift "a hook is dead only when it names script paths and none exists; the hash is event plus command"
func TestDeadHooks(t *testing.T) {
	h := newTempHome(t)
	h.write("bin/alive.sh", "#!/bin/sh\n")
	alive, gone := h.path("bin/alive.sh"), h.path("bin/gone.sh")
	commands := []string{"sh '" + alive + "'", "sh '" + gone + "'", "echo no-path", "sh '" + gone + "' '" + alive + "'"}
	var groups []string
	for _, c := range commands {
		q, _ := json.Marshal(c)
		groups = append(groups, `{"hooks": [{"type": "command", "command": `+string(q)+`, "timeout": 30, "async": true}]}`)
	}
	h.write(".claude/settings.json", `{"hooks": {"Stop": [`+strings.Join(groups, ",")+`]}}`)
	inv := Read(h.roots())
	var dead []bool
	for _, hk := range inv.Hooks {
		dead = append(dead, hk.Dead)
	}
	if !reflect.DeepEqual(dead, []bool{false, true, false, false}) {
		t.Errorf("dead = %v", dead)
	}
	first := inv.Hooks[0]
	if first.Hash != hashes.Sha("Stop|"+commands[0]) {
		t.Errorf("hash = %q", first.Hash)
	}
	if first.Timeout == nil || *first.Timeout != 30 || !first.Async || first.Matcher != nil {
		t.Errorf("first = %+v", first)
	}
	if first.ID != "claude:hook:"+hashes.Sha("|Stop||"+commands[0]) {
		t.Errorf("id = %q", first.ID)
	}
	if !reflect.DeepEqual(inv.Hooks[1].Paths, []string{gone}) {
		t.Errorf("paths = %q", inv.Hooks[1].Paths)
	}
}

// Swift: InventoryTests.swift "a duplicated event key counts once, with the last value, as JSON.parse has it"
func TestDuplicateKeys(t *testing.T) {
	h := newTempHome(t)
	group := func(command string) string {
		return `[{"hooks": [{"type": "command", "command": "` + command + `"}]}]`
	}
	h.write(".claude/settings.json", `{"hooks": {"Stop": `+group("echo first")+`, "Stop": `+group("echo last")+`}}`)
	inv := Read(h.roots())
	if len(inv.Hooks) != 1 || inv.Hooks[0].Command != "echo last" {
		t.Errorf("hooks = %+v", inv.Hooks)
	}
}

// Swift: InventoryTests.swift "hooks come from settings.json and hooks.json; a file that is not valid JSON is reported, not fatal"
func TestInvalidJSON(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/settings.json", "{ not json")
	h.write(".codex/hooks.json", hookConfig("Stop", "echo codex"))
	inv := Read(h.roots())
	if len(inv.Hooks) != 1 || inv.Hooks[0].CLI != Codex {
		t.Errorf("hooks = %+v", inv.Hooks)
	}
	// Two lines since G-fix.13 (Swift has one): the hooks line, and what else hangs on the file (plugins, overrides).
	if len(inv.Problems) != 2 || !strings.Contains(inv.Problems[0], "settings.json") || !strings.Contains(inv.Problems[0], "not valid JSON") ||
		!strings.Contains(inv.Problems[1], "settings.json is not valid JSON, so enabled plugins and skill overrides are not known.") {
		t.Errorf("problems = %q", inv.Problems)
	}
}

// Swift: InventoryTests.swift "projects come from Claude session logs and Codex project tables; worktrees, home and missing folders are skipped"
func TestProjects(t *testing.T) {
	h := newTempHome(t)
	alpha, beta := h.path("work/alpha"), h.path("work/beta")
	cwd := func(path string) string {
		return `{"type":"user","cwd":"` + path + `","timestamp":"2026-10-01T10:00:00Z"}`
	}
	h.write(".claude/skills/glob/SKILL.md", skillFile("glob"))
	h.write(".claude/settings.json", hookConfig("Stop", "echo shared"))
	h.write(".claude/projects/-enc-alpha/s1.jsonl", "{\"type\":\"file-history-snapshot\"}\n"+cwd(alpha))
	h.write(".claude/projects/-enc-wt/s1.jsonl", cwd(alpha+"/.claude/worktrees/feature"))
	h.write(".claude/projects/-enc-home/s1.jsonl", cwd(h.root))
	h.write(".claude/projects/-enc-gone/s1.jsonl", cwd(h.path("work/deleted")))
	h.write("work/alpha/.claude/worktrees/feature/.claude/settings.json", hookConfig("Stop", "echo copy-in-worktree"))
	h.write("work/alpha/.claude/skills/pskill/SKILL.md", skillFile("pskill", "project skill"))
	h.write("work/alpha/.claude/agents/pagent.md", "---\nname: pagent\ndescription: project agent\n---\n")
	h.write("work/alpha/.claude/settings.json", hookConfig("Stop", "echo shared"))
	h.write("work/alpha/.claude/settings.local.json", hookConfig("PreToolUse", "sh '"+alpha+"/gone.sh'"))
	h.write(".codex/config.toml", "model = \"x\"\n[projects.\""+beta+"\"]\ntrust_level = \"trusted\"\n[projects.\""+h.path("work/missing")+"\"]\ntrust_level = \"trusted\"\n")
	h.write("work/beta/.claude/skills/bskill/SKILL.md", skillFile("bskill", "b"))

	r := h.roots()
	found := DiscoverProjects(r)
	slices.Sort(found)
	if want := []string{alpha, beta}; !reflect.DeepEqual(found, want) {
		t.Fatalf("projects = %q, want %q", found, want)
	}

	inv := Read(r)
	if it := item(inv, "glob"); it.Scope != ScopeGlobal || it.Project != nil {
		t.Errorf("glob = %+v", it)
	}
	ps := item(inv, "pskill")
	if ps.Scope != ScopeProject || ps.Project == nil || *ps.Project != alpha || ps.Kind != KindSkill || ps.Removable {
		t.Errorf("pskill = %+v", ps)
	}
	if ps.ID != "claude:skill:project:"+hashes.Sha(alpha)+":pskill" {
		t.Errorf("pskill id = %q", ps.ID)
	}
	if item(inv, "pagent").Kind != KindAgent {
		t.Error("pagent is not an agent")
	}
	if b := item(inv, "bskill"); b.Project == nil || *b.Project != beta {
		t.Errorf("bskill = %+v", b)
	}
	var got [][2]string
	for _, hk := range inv.Hooks {
		if hk.Project != nil && *hk.Project == alpha {
			got = append(got, [2]string{hk.Event, strings.TrimPrefix(hk.File, alpha)})
			if hk.Scope != ScopeProject || hk.Removable {
				t.Errorf("project hook %+v", hk)
			}
			if hk.Event == "PreToolUse" && !hk.Dead {
				t.Error("the PreToolUse hook names a missing script")
			}
		}
	}
	slices.SortFunc(got, func(a, b [2]string) int { return strings.Compare(a[0], b[0]) })
	if want := [][2]string{{"PreToolUse", "/.claude/settings.local.json"}, {"Stop", "/.claude/settings.json"}}; !reflect.DeepEqual(got, want) {
		t.Errorf("project hooks = %q", got)
	}
	if hookByCommand(inv, "echo copy-in-worktree") != nil {
		t.Error("a worktree copy was read")
	}

	// The same hook in the global file and in a project: one hash, two ids.
	var same []Hook
	for _, hk := range inv.Hooks {
		if hk.Command == "echo shared" {
			same = append(same, hk)
		}
	}
	if len(same) != 2 {
		t.Fatalf("shared hooks = %d", len(same))
	}
	if same[0].Hash != same[1].Hash || same[0].ID == same[1].ID || same[0].Key() == same[1].Key() {
		t.Errorf("shared = %+v", same)
	}
	for _, hk := range same {
		if hk.Scope == ScopeGlobal && !strings.HasPrefix(hk.ID, "claude:hook:") {
			t.Errorf("global id %q", hk.ID)
		}
	}
}

// Swift: InventoryTests.swift "the project hook shows the runs of its event plus command, from every log"
func TestProjectHookUsage(t *testing.T) {
	h := newTempHome(t)
	alpha := h.path("work/alpha")
	h.write(".claude/projects/-enc-alpha/s1.jsonl", `{"type":"user","cwd":"`+alpha+`"}`+"\n")
	run := func(exit string) string {
		return `{"type":"attachment","timestamp":"2026-10-02T10:00:00Z","attachment":{"type":"hook_success","hookEvent":"Stop","command":"echo shared","durationMs":1,"exitCode":` + exit + `}}`
	}
	h.write(".claude/projects/-enc-alpha/s2.jsonl", run("0")+"\n"+run("1"))
	h.write(".claude/settings.json", hookConfig("Stop", "echo shared"))
	h.write("work/alpha/.claude/settings.json", hookConfig("Stop", "echo shared"))
	r := h.roots()
	input := usage.Ready(scanOf(t, r))
	inv := AttachUsage(Read(r), &input, mustTime(t, "2026-11-02T00:00:00Z"))
	var hook *Hook
	for i := range inv.Hooks {
		if inv.Hooks[i].Command == "echo shared" && inv.Hooks[i].Scope == ScopeProject {
			hook = &inv.Hooks[i]
		}
	}
	if hook == nil || hook.Usage == nil || hook.Usage.Runs != 2 || hook.Usage.Errors != 1 {
		t.Fatalf("hook = %+v", hook)
	}
	if want := Counted(2, ptr("2026-10-02"), ptr(1)); !reflect.DeepEqual(hook.Cells.Claude, want) {
		t.Errorf("cell = %+v", hook.Cells.Claude)
	}
}

// Swift: InventoryTests.swift "an empty home gives an empty inventory"
func TestEmptyHome(t *testing.T) {
	h := newTempHome(t)
	r := h.roots()
	if got := DiscoverProjects(r); len(got) != 0 {
		t.Errorf("projects = %q", got)
	}
	inv := Read(r)
	if len(inv.Items) != 0 || len(inv.Hooks) != 0 || len(inv.Problems) != 0 {
		t.Errorf("inv = %+v", inv)
	}
	// The wire form has arrays, not nulls.
	data, _ := json.Marshal(inv)
	for _, want := range []string{`"items":[]`, `"hooks":[]`, `"problems":[]`} {
		if !strings.Contains(string(data), want) {
			t.Errorf("%s not in %s", want, data)
		}
	}
}

// Swift: InventoryTests.swift "values of env keys in settings never appear in any output"
func TestSecretsStayOut(t *testing.T) {
	h := newTempHome(t)
	const secret = "sk-test-CANARY-1f9d"
	h.write(".claude/settings.json", hookConfig("Stop", "echo hi", secret))
	h.write(".claude/skills/s/SKILL.md", skillFile("s"))
	h.write("work/p/.claude/settings.json", hookConfig("Stop", "echo project", secret))
	h.write(".claude/projects/-enc-p/s1.jsonl", `{"type":"user","cwd":"`+h.path("work/p")+`"}`+"\n")
	r := h.roots()
	result := scanOf(t, r)
	input := usage.Ready(result)
	attached := AttachUsage(Read(r), &input, mustTime(t, "2026-11-02T00:00:00Z"))
	a, _ := json.Marshal(attached)
	b, _ := json.Marshal(result)
	rows, _ := json.Marshal(BuildLoadoutRows(Read(r), input, mustTime(t, "2026-11-02T00:00:00Z")))
	cache, err := os.ReadFile(usage.CachePath(r.Data))
	if err != nil {
		t.Fatal(err)
	}
	for name, out := range map[string][]byte{"inventory": a, "usage": b, "loadout.rows": rows, "cache": cache} {
		if strings.Contains(string(out), secret) {
			t.Errorf("the secret is in the %s output", name)
		}
	}
	if len(attached.Hooks) != 2 {
		t.Errorf("hooks = %d", len(attached.Hooks))
	}
}

// Swift: InventoryTests.swift "readItemFile caps the text and says so"
func TestItemFile(t *testing.T) {
	h := newTempHome(t)
	file, ok := ReadItemFile(h.write("big.md", strings.Repeat("x", 70_000)))
	if !ok || file.Size != 70_000 || len(file.Text) != 64*1024 || !file.Truncated {
		t.Errorf("big = %d %d %v %v", file.Size, len(file.Text), file.Truncated, ok)
	}
	small, ok := ReadItemFile(h.write("small.md", "hi"))
	if !ok || small.Text != "hi" || small.Truncated {
		t.Errorf("small = %+v", small)
	}
	if _, ok := ReadItemFile(h.path("nope")); ok {
		t.Error("a missing file was read")
	}
}

// Swift: InventoryTests.swift "a root under the real home is refused when SPACEVIBE_TEST=1, so no read or scan can reach it"
func TestGuardRefusesRealHome(t *testing.T) {
	real, err := roots.RealHome()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := roots.Resolve(config.Config{Test: true, UserHome: real}, real); err == nil {
		t.Error("a root under the real home was accepted")
	}
}

// Swift: InventoryTests.swift "items and hooks survive a JSON round trip"
func TestCodableRoundTrip(t *testing.T) {
	r, _ := fixtureRoots(t)
	input := usage.Ready(scanOf(t, r))
	inv := AttachUsage(Read(r), &input, fixtureNow(t))
	data, err := json.Marshal(inv)
	if err != nil {
		t.Fatal(err)
	}
	var decoded Snapshot
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(decoded, inv) {
		t.Error("decoded snapshot differs from the original")
	}
	if len(inv.Items) == 0 || len(inv.Hooks) == 0 {
		t.Error("the fixture inventory is empty")
	}
}

// Extra (G2.1): a cell has the shape of UsageCellState.encode.
func TestCellJSON(t *testing.T) {
	for cell, want := range map[string]Cell{
		`{"state":"counted","runs":3,"last":"2026-10-20"}`:                 Counted(3, ptr("2026-10-20"), nil),
		`{"state":"counted","runs":0,"errors":2,"last":null}`:              Counted(0, nil, ptr(2)),
		`{"state":"pending","reason":"Added in the last 24 hours"}`:        Pending("Added in the last 24 hours"),
		`{"state":"unmeasurable","reason":"Codex does not log hook runs"}`: Unmeasurable(CodexHooksReason),
		`{"state":"missing"}`: Missing(),
	} {
		got, err := json.Marshal(want)
		if err != nil || string(got) != cell {
			t.Errorf("marshal = %s (%v), want %s", got, err, cell)
		}
		var back Cell
		if err := json.Unmarshal([]byte(cell), &back); err != nil || !reflect.DeepEqual(back, want) {
			t.Errorf("unmarshal %s = %+v (%v)", cell, back, err)
		}
	}
	var c Cell
	if json.Unmarshal([]byte(`{"state":"weird"}`), &c) == nil {
		t.Error("an unknown state was accepted")
	}
}

// Extra (G2.1), H14: a skill whose folder is NFD in one CLI and NFC in the other. Swift compares and hashes
// strings by canonical equivalence: observed with the 6.3 toolchain, the two are one row, both items report
// inOther true, and a usage count under either spelling counts for both (2 sessions). Go compares bytes: two
// rows, inOther false, each item counts only the sessions that spelled its name the same way. This pins
// the Go behaviour; folding needs Unicode normalization tables (not in the standard library).
func TestNFDSkillNames(t *testing.T) {
	h := newTempHome(t)
	nfc, nfd := "café", "café"
	h.write(".claude/skills/"+nfd+"/SKILL.md", "---\ndescription: nfd claude\n---\n")
	h.write(".codex/skills/"+nfc+"/SKILL.md", "---\ndescription: nfc codex\n---\n")
	call := func(name string) string {
		return `{"type":"assistant","timestamp":"2026-10-0` + map[string]string{nfc: "1", nfd: "2"}[name] + `T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"` + name + `"}}]}}` + "\n"
	}
	h.write(".claude/projects/p/s1.jsonl", call(nfc))
	h.write(".claude/projects/p/s2.jsonl", call(nfd))
	r := h.roots()
	input := usage.Ready(scanOf(t, r))
	inv := AttachUsage(Read(r), &input, mustTime(t, "2026-11-02T00:00:00Z"))
	claude, codex := item(inv, nfd, Claude), item(inv, nfc, Codex)
	if claude == nil || codex == nil {
		t.Fatalf("items = %+v", inv.Items)
	}
	if claude.InOther || codex.InOther {
		t.Error("Go folded NFC and NFD names into one row (it compares bytes)")
	}
	if claude.Key() == codex.Key() {
		t.Error("the keys are equal")
	}
	if got := claude.Cells.Claude; got.State != StateCounted || got.Runs != 1 {
		t.Errorf("NFD claude cell = %+v, want counted 1 (Swift: 2)", got)
	}
	if got := codex.Cells.Claude; got.State != StateMissing {
		// The NFC row exists only in Codex; its Claude cell is missing, where Swift shows the shared row.
		t.Errorf("NFC codex row, Claude cell = %+v", got)
	}
}

// Extra (G2.1), H14: a project whose folder name holds a precomposed letter (NFC on disk). Go keeps the path
// bytes it was given, so the hook id hashes that file name. Swift builds the file name through URL.path,
// which came out decomposed (NFD, U+0301) for the same tree (observed with the 6.3 toolchain): the id there
// was 6971ab843d4c where Go gave edc24f23fe6a for the home5 test tree, and `file` differed in the same way
// while `project` stayed NFC. The Matrix shell treats ids as opaque, so a mixed-engine run only needs one
// engine per session; the difference is recorded, not fixed (no normalization tables in the standard library).
func TestNFCProjectHookID(t *testing.T) {
	h := newTempHome(t)
	project := h.path("work/pr\u00f3j")
	h.write(".claude/projects/-enc-proj/s1.jsonl", `{"type":"user","cwd":"`+project+`"}`+"\n")
	file := h.write("work/pr\u00f3j/.claude/settings.json", hookConfig("Stop", "echo p"))
	inv := Read(h.roots())
	hook := hookByCommand(inv, "echo p")
	if hook == nil || hook.File != file || hook.Project == nil || *hook.Project != project {
		t.Fatalf("hook = %+v", hook)
	}
	if want := "claude:hook:" + hashes.Sha("|Stop|Edit|echo p|"+file); hook.ID != want {
		t.Errorf("id = %q, want %q (the seed holds the file bytes as given)", hook.ID, want)
	}
}
