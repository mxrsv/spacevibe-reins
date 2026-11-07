package mutate

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/textjs"
	"spacevibe.dev/core/internal/usage"
)

// The tests below run on a private copy of the fixture HOME (newCopy), like MutateTests.swift.

func (h copyHome) item(name string, kind inventory.Kind, cli usage.CLI) inventory.Item {
	h.t.Helper()
	for _, it := range inventory.Read(h.r).Items {
		if it.Name == name && it.Kind == kind && it.CLI == cli {
			return it
		}
	}
	h.t.Fatalf("no %s %s for %s", kind, name, cli)
	return inventory.Item{}
}

func (h copyHome) hook(match func(inventory.Hook) bool) inventory.Hook {
	h.t.Helper()
	for _, hk := range inventory.Read(h.r).Hooks {
		if match(hk) {
			return hk
		}
	}
	h.t.Fatal("no such hook")
	return inventory.Hook{}
}

func (h copyHome) settingsDoc() *ojson.Document {
	h.t.Helper()
	doc, err := ojson.ParseString(h.read(".claude/settings.json"))
	if err != nil {
		h.t.Fatal(err)
	}
	return doc
}

func (h copyHome) deadClaudeHooks() int {
	n := 0
	for _, hk := range inventory.Read(h.r).Hooks {
		if hk.Dead {
			n++
		}
	}
	return n
}

func (h copyHome) commands() []string {
	var out []string
	for _, hk := range inventory.Read(h.r).Hooks {
		out = append(out, hk.Command)
	}
	return out
}

func (h copyHome) envToken(doc *ojson.Document) string {
	env, _ := doc.Get(ojson.Key("env"), ojson.Key("EXAMPLE_TOKEN"))
	s, _ := env.StringValue()
	return s
}

// Swift: MutateTests.swift "removing a linked skill leaves its target; undo makes the link again"
func TestRemoveLinkedSkill(t *testing.T) {
	h := newCopy(t)
	h.write("shared/linked/SKILL.md", "---\nname: linked\ndescription: shared\n---\n")
	h.symlink(h.path("shared/linked"), ".claude/skills/linked")
	entry := must(RemoveItem(h.r, h.item("linked", inventory.KindSkill, inventory.Claude).ID))
	if len(entry.Ops) != 1 || entry.Ops[0].Type() != "link-removed" || !exists(h.path("shared/linked/SKILL.md")) {
		t.Errorf("ops %v", entry.Ops)
	}
	must(Undo(h.r, entry.ID))
	if target, _ := os.Readlink(h.path(".claude/skills/linked")); target != h.path("shared/linked") {
		t.Errorf("link target %q", target)
	}
}

// Swift: MutateTests.swift "a removed skill folder is in the app trash with its bytes, not deleted"
func TestRemovedGoesToTrash(t *testing.T) {
	h := newCopy(t)
	original := h.read(".claude/skills/tdd/SKILL.md")
	entry := must(RemoveItem(h.r, h.item("tdd", inventory.KindSkill, inventory.Claude).ID))
	moved, _ := entry.Ops[0].str("to")
	if !strings.HasPrefix(moved, filepath.Join(h.r.Data, "trash")) {
		t.Errorf("moved to %q", moved)
	}
	if data, _ := os.ReadFile(moved + "/SKILL.md"); string(data) != original {
		t.Error("the trashed skill lost its bytes")
	}
}

// Swift: MutateTests.swift "project-scoped and plugin-owned items are read-only (403)"
func TestReadOnlyItems(t *testing.T) {
	h := newCopy(t)
	h.write("work/spacevibe-bench/.claude/skills/proj-skill/SKILL.md", "---\nname: proj-skill\ndescription: p\n---\n")
	h.write("work/spacevibe-bench/.claude/settings.json", `{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo project"}]}]}}`)
	snap := inventory.Read(h.r)
	var skill, plugin inventory.Item
	var hook inventory.Hook
	for _, it := range snap.Items {
		switch it.Name {
		case "proj-skill":
			skill = it
		case "neon-postgres":
			plugin = it
		}
	}
	for _, hk := range snap.Hooks {
		if hk.Command == "echo project" {
			hook = hk
		}
	}
	if skill.Scope != inventory.ScopeProject || skill.Removable || hook.Scope != inventory.ScopeProject {
		t.Fatalf("skill %+v hook %+v", skill, hook)
	}
	before := h.tree()
	for _, c := range []struct{ id, text string }{{skill.ID, "project folder"}, {hook.ID, "project folder"}, {plugin.ID, "belongs to a plugin"}} {
		_, err := RemoveItem(h.r, c.id)
		if m := wantErr(t, err, 403); !strings.Contains(m, c.text) {
			t.Errorf("message %q", m)
		}
	}
	if !maps_equal(h.tree(), before) {
		t.Error("a refused removal changed the tree")
	}
	// Reading is allowed: a project skill can be copied into the other CLI.
	if e := must(CopyToOther(h.r, skill.ID)); e.Label != "Copied skill proj-skill to Codex" {
		t.Errorf("label %q", e.Label)
	}
}

// Swift: MutateTests.swift "names: only lowercase letters, digits and dashes, 1 to 64 characters"
func TestNameRules(t *testing.T) {
	h := newCopy(t)
	for _, name := range []string{"../evil", "a/b", ".hidden", "UP", "", "-lead", "has space", strings.Repeat("a", 65)} {
		_, err := AddSkill(h.r, []usage.CLI{inventory.Claude}, name, "x", "")
		if m := wantErr(t, err, 400); m != "Use lowercase letters, numbers and dashes for the name." {
			t.Errorf("%q: %q", name, m)
		}
		if _, err := AddAgent(h.r, []usage.CLI{inventory.Codex}, name, "x", ""); err == nil {
			t.Errorf("addAgent accepted %q", name)
		}
	}
	must(AddSkill(h.r, []usage.CLI{inventory.Claude}, "9"+strings.Repeat("a", 63), "x", ""))
	must(AddSkill(h.r, []usage.CLI{inventory.Claude}, "a-b-9", "x", ""))
}

// Swift: MutateTests.swift "a name that exists in the second CLI leaves nothing behind in the first"
func TestExistingNameInSecondCLI(t *testing.T) {
	h := newCopy(t)
	h.write(".codex/skills/codex-only/SKILL.md", "---\nname: codex-only\ndescription: c\n---\n")
	h.write(".claude/agents/dup.md", "---\nname: dup\ndescription: d\n---\n")
	before := h.tree()
	_, err := AddSkill(h.r, []usage.CLI{inventory.Claude, inventory.Codex}, "codex-only", "x", "")
	if m := wantErr(t, err, 409); m != "Codex already has a skill named codex-only." {
		t.Errorf("message %q", m)
	}
	_, err = AddAgent(h.r, []usage.CLI{inventory.Codex, inventory.Claude}, "dup", "x", "")
	wantErr(t, err, 409)
	if !maps_equal(h.tree(), before) || len(historyOf(t, h.r)) != 0 {
		t.Error("something was left behind")
	}
}

// Swift: MutateTests.swift "hooks: a failure on the second CLI puts the first file back and records nothing"
func TestHookRollback(t *testing.T) {
	h := newCopy(t)
	h.write(".codex/hooks.json", "{broken")
	before := h.tree()
	_, err := AddHook(h.r, []usage.CLI{inventory.Claude, inventory.Codex}, "Stop", nil, "echo x", nil)
	wantErr(t, err, 409)
	if !maps_equal(h.tree(), before) || len(historyOf(t, h.r)) != 0 {
		t.Error("the first file was not put back, or an entry was recorded")
	}
}

// Swift: MutateTests.swift "hooks: validation wording and the per-CLI event list"
func TestHookValidation(t *testing.T) {
	h := newCopy(t)
	for _, c := range []struct {
		clis           []usage.CLI
		event, command string
		message        string
	}{
		{[]usage.CLI{inventory.Claude}, "Stop", "   ", "Enter the command this hook runs."},
		{nil, "Stop", "echo", "Pick at least one CLI."},
		{[]usage.CLI{inventory.Codex}, "TeammateIdle", "echo", "Codex has no TeammateIdle event."},
		{[]usage.CLI{inventory.Claude, inventory.Codex}, "PostToolUseFailure", "echo", "Codex has no PostToolUseFailure event."},
	} {
		_, err := AddHook(h.r, c.clis, c.event, nil, c.command, nil)
		if m := wantErr(t, err, 400); m != c.message {
			t.Errorf("message %q, want %q", m, c.message)
		}
	}
	if len(historyOf(t, h.r)) != 0 {
		t.Error("an entry was recorded")
	}
}

// Swift: MutateTests.swift "copying a hook: into Claude Code when it knows the event, never into Codex"
func TestCopyHook(t *testing.T) {
	h := newCopy(t)
	h.write(".codex/hooks.json", `{"hooks":{"Interrupt":[{"hooks":[{"type":"command","command":"echo bye"}]}],"Stop":[{"hooks":[{"type":"command","command":"echo stop-from-codex"}]}]}}`)
	interrupt := h.hook(func(hk inventory.Hook) bool { return hk.Command == "echo bye" })
	stop := h.hook(func(hk inventory.Hook) bool { return hk.Command == "echo stop-from-codex" })
	claudeHook := h.hook(func(hk inventory.Hook) bool { return hk.CLI == inventory.Claude && hk.Event == "SessionStart" })

	_, err := CopyToOther(h.r, interrupt.ID)
	if m := wantErr(t, err, 400); m != "Claude Code has no Interrupt event." {
		t.Errorf("message %q", m)
	}
	_, err = CopyToOther(h.r, claudeHook.ID)
	if m := wantErr(t, err, 400); m != "SpaceVibe does not copy hooks into Codex." {
		t.Errorf("message %q", m)
	}
	if e := must(CopyToOther(h.r, stop.ID)); e.Label != "Added Stop hook to Claude Code" {
		t.Errorf("label %q", e.Label)
	}
	if !slices.Contains(h.commands(), "echo stop-from-codex") {
		t.Error("the hook is not in Claude Code")
	}
}

// Swift: MutateTests.swift "a copied skill is a new item: its files are not older than the copy"
func TestCopiedSkillIsFresh(t *testing.T) {
	h := newCopy(t)
	var source inventory.Item
	for _, it := range inventory.Read(h.r).Items {
		if it.CLI == inventory.Claude && it.Kind == inventory.KindSkill && it.Removable {
			source = it
			break
		}
	}
	old := time.Unix(1_577_836_800, 0)
	if err := os.Chtimes(filepath.Join(source.Path, "SKILL.md"), old, old); err != nil {
		t.Fatal(err)
	}
	must(CopyToOther(h.r, source.ID))
	target := h.item(source.Name, inventory.KindSkill, inventory.Codex)
	info, err := os.Stat(filepath.Join(target.Path, "SKILL.md"))
	if err != nil {
		t.Fatal(err)
	}
	if time.Since(info.ModTime()) > 120*time.Second {
		t.Errorf("the copy is %v old", time.Since(info.ModTime()))
	}
}

// Swift: MutateTests.swift "an agent keeps its quotes and backslashes through markdown and TOML"
func TestAgentRoundTrip(t *testing.T) {
	h := newCopy(t)
	instructions := "Say \"hi\" \\ always.\nSecond line."
	description := "Reads \"quotes\" and \\ slashes"
	must(AddAgent(h.r, []usage.CLI{inventory.Claude}, "round", description, instructions))
	toCodex := must(CopyToOther(h.r, h.item("round", inventory.KindAgent, inventory.Claude).ID))
	if toCodex.Label != "Copied agent round to Codex" {
		t.Errorf("label %q", toCodex.Label)
	}
	toml := h.read(".codex/agents/round.toml")
	if tomlInstructions(toml) != instructions || tomlDescription(toml) != description {
		t.Errorf("toml %q", toml)
	}
	// And back: a Codex-only agent becomes a Claude Code file with the same words.
	if err := os.Remove(h.path(".claude/agents/round.md")); err != nil {
		t.Fatal(err)
	}
	must(CopyToOther(h.r, h.item("round", inventory.KindAgent, inventory.Codex).ID))
	markdown := h.read(".claude/agents/round.md")
	if inventory.ParseFrontmatter(markdown)["description"] != description {
		t.Errorf("markdown description in %q", markdown)
	}
	if strings.TrimSpace(stripHeader(markdown)) != instructions {
		t.Errorf("markdown body %q", stripHeader(markdown))
	}
}

// Swift: MutateTests.swift "JavaScript trim and whitespace collapse"
func TestJSText(t *testing.T) {
	if got := textjs.Trim("\u00a0 a b \ufeff\n"); got != "a b" {
		t.Errorf("trim %q", got)
	}
	if got := yamlValue("  one\t\ttwo \n three\u2003"); got != `"one two three"` {
		t.Errorf("yamlValue %q", got)
	}
	if got := textjs.Trim(" \u200bx"); got != "\u200bx" {
		t.Errorf("zero width %q", got)
	}
}

// Swift: MutateTests.swift "undo when the file changed since: the hook is reversed, the hand edit and the secrets stay"
func TestUndoAfterHandEdit(t *testing.T) {
	h := newCopy(t)
	deadBefore := h.deadClaudeHooks()
	entry := must(RemoveDeadHooks(h.r, inventory.Claude))
	if len(entry.Ops) != 2 || h.deadClaudeHooks() != 0 {
		t.Fatalf("ops %d, dead %d", len(entry.Ops), h.deadClaudeHooks())
	}
	// A change by hand after the removal: the exact bytes no longer match, so undo must re-add the hooks only.
	edited := must(h.settingsDoc().Set(ojson.Path("model"), ojson.String("by-hand")))
	h.write(".claude/settings.json", edited.Text())
	must(Undo(h.r, entry.ID))

	if h.deadClaudeHooks() != deadBefore {
		t.Errorf("dead hooks %d, want %d", h.deadClaudeHooks(), deadBefore)
	}
	doc := h.settingsDoc()
	if model, _ := doc.Get(ojson.Key("model")); !valueIs(model, "by-hand") || h.envToken(doc) != canary {
		t.Error("the hand edit or the secret is gone")
	}
}

func valueIs(v ojson.Value, want string) bool {
	s, ok := v.StringValue()
	return ok && s == want
}

// Swift: MutateTests.swift "undo of one hook while a later hook stays"
func TestUndoOlderHook(t *testing.T) {
	h := newCopy(t)
	one := []usage.CLI{inventory.Claude}
	first := must(AddHook(h.r, one, "Stop", nil, "echo first", nil))
	three := 3.0
	second := must(AddHook(h.r, one, "Stop", nil, "echo second", &three))
	must(Undo(h.r, first.ID))
	if c := h.commands(); slices.Contains(c, "echo first") || !slices.Contains(c, "echo second") {
		t.Errorf("commands after the first undo: %v", c)
	}
	must(Undo(h.r, second.ID))
	if slices.Contains(h.commands(), "echo second") {
		t.Error("echo second is still there")
	}
	if h.envToken(h.settingsDoc()) != canary {
		t.Error("the secret is gone")
	}
}

// Swift: MutateTests.swift "hook ops written by the Node core (no restore data) are undone by editing the hooks"
func TestUndoNodeHookOps(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	file := home.write(".claude/settings.json", "{\n  \"env\": {\"T\": \""+canary+"\"},\n  \"hooks\": {\n    \"Stop\": [\n      {\n        \"hooks\": [\n          { \"type\": \"command\", \"command\": \"echo kept\" },\n          { \"type\": \"command\", \"command\": \"echo added\", \"timeout\": 5 }\n        ]\n      }\n    ]\n  }\n}")
	home.write(".spacevibe/journal.json", `[
  { "id": "aaaaaaaa-0000-0000-0000-000000000001", "at": "2026-11-02T10:00:00.000Z", "label": "Added Stop hook to Claude Code",
    "ops": [ { "type": "hook-added", "file": "`+file+`", "event": "Stop", "matcher": null, "hook": { "type": "command", "command": "echo added", "timeout": 5 } } ] },
  { "id": "aaaaaaaa-0000-0000-0000-000000000002", "at": "2026-11-02T09:00:00.000Z", "label": "Removed Edit hook from Claude Code",
    "ops": [ { "type": "hook-removed", "file": "`+file+`", "event": "PreToolUse", "matcher": "Edit", "hook": { "type": "command", "command": "echo gone" } } ] }
]`)
	if l := must(Undo(r, "aaaaaaaa-0000-0000-0000-000000000001")); l != "Added Stop hook to Claude Code" {
		t.Errorf("label %q", l)
	}
	if l := must(Undo(r, "aaaaaaaa-0000-0000-0000-000000000002")); l != "Removed Edit hook from Claude Code" {
		t.Errorf("label %q", l)
	}
	var commands []string
	for _, hk := range inventory.Read(r).Hooks {
		commands = append(commands, hk.Command)
	}
	slices.Sort(commands)
	if !slices.Equal(commands, []string{"echo gone", "echo kept"}) {
		t.Errorf("commands %v", commands)
	}
	doc := must(ojson.ParseString(home.read(".claude/settings.json")))
	matcher, _ := doc.Get(ojson.Key("hooks"), ojson.Key("PreToolUse"))
	group, _ := matcher.Element(0)
	if m, _ := group.Member("matcher"); !valueIs(m, "Edit") {
		t.Error("the Edit matcher is missing")
	}
	if tok, _ := doc.Get(ojson.Key("env"), ojson.Key("T")); !valueIs(tok, canary) {
		t.Error("the secret is gone")
	}
}

// Swift: MutateTests.swift "no error or label quotes a secret from settings, even when the file is broken"
func TestCanaryNeverLeaks(t *testing.T) {
	h := newCopy(t)
	claude := []usage.CLI{inventory.Claude}
	h.write(".claude/settings.json", `{"env": {"T": "`+canary+`"}, "hooks": `)
	_, err := AddHook(h.r, claude, "Stop", nil, "echo x", nil)
	if m := wantErr(t, err, 409); strings.Contains(m, canary) {
		t.Errorf("message %q", m)
	}
	if !strings.Contains(h.read(".claude/settings.json"), canary) {
		t.Error("the file lost its secret")
	}

	h.write(".claude/settings.json", `{"env": {"T": "`+canary+`"}, "hooks": {"Stop": 7}}`)
	_, err = AddHook(h.r, claude, "Stop", nil, "echo x", nil)
	if m := wantErr(t, err, 409); strings.Contains(m, canary) {
		t.Errorf("message %q", m)
	}

	h.write(".claude/settings.json", `{"env": {"T": "`+canary+`"}}`)
	entry := must(AddHook(h.r, claude, "Stop", nil, "echo x", nil))
	journal, _ := os.ReadFile(filepath.Join(h.r.Data, "journal.json"))
	if strings.Contains(string(journal), canary) || strings.Contains(entry.Label, canary) || !strings.Contains(h.read(".claude/settings.json"), canary) {
		t.Error("the secret leaked, or the file lost it")
	}
}
