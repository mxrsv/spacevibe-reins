package inventory

import (
	"slices"
	"strings"
	"testing"
)

// G-fix.13 and G-fix.14: what the reader used to drop without a word is a `problems` line now. Fixed sentences with a
// path and a count; never file content. The fixtures have none of these cases, so the golden snapshots do not move.

const secretText = "SECRET-CONTENT-7731"

func hasProblem(inv Snapshot, want string) bool { return slices.Contains(inv.Problems, want) }

func noLeak(t *testing.T, inv Snapshot) {
	t.Helper()
	if strings.Contains(strings.Join(inv.Problems, "|"), secretText) {
		t.Errorf("a problem quotes the file: %q", inv.Problems)
	}
}

// A plugin's hooks.json and installed_plugins.json that cannot be used, and a settings.json that hides the plugins.
func TestPluginAndSettingsFailuresAreReported(t *testing.T) {
	h := newTempHome(t)
	plugin := h.path("cache/acme")
	h.write("cache/acme/skills/s/SKILL.md", skillFile("s"))
	h.write("cache/acme/hooks/hooks.json", "{ not json "+secretText)
	h.write(".claude/plugins/installed_plugins.json", `{"plugins": {"acme@market": [{"installPath": "`+plugin+`"}]}}`)
	h.write(".claude/settings.json", `{"enabledPlugins": {"acme@market": true}}`)

	inv := Read(h.roots())
	if want := plugin + "/hooks/hooks.json is not valid JSON, so the hooks of the plugin acme are not shown."; !hasProblem(inv, want) {
		t.Errorf("plugin hooks.json: %q", inv.Problems)
	}
	if item(inv, "s") == nil {
		t.Error("the plugin skill is still listed")
	}
	noLeak(t, inv)

	// Too large.
	h.write("cache/acme/hooks/hooks.json", strings.Repeat(" ", maxJSONBytes+1))
	inv = Read(h.roots())
	if want := plugin + "/hooks/hooks.json is too large to read, so the hooks of the plugin acme are not shown."; !hasProblem(inv, want) {
		t.Errorf("too large: %q", inv.Problems)
	}

	// A missing hooks.json is normal: no line.
	h2 := newTempHome(t)
	h2.write("cache/acme/skills/s/SKILL.md", skillFile("s"))
	h2.write(".claude/plugins/installed_plugins.json", `{"plugins": {"acme@market": [{"installPath": "`+h2.path("cache/acme")+`"}]}}`)
	h2.write(".claude/settings.json", `{"enabledPlugins": {"acme@market": true}}`)
	if inv := Read(h2.roots()); len(inv.Problems) != 0 {
		t.Errorf("a plugin without hooks.json: %q", inv.Problems)
	}

	// installed_plugins.json invalid.
	h3 := newTempHome(t)
	h3.write(".claude/plugins/installed_plugins.json", "[ "+secretText)
	h3.write(".claude/settings.json", `{"enabledPlugins": {"acme@market": true}}`)
	inv = Read(h3.roots())
	if want := h3.path(".claude/plugins/installed_plugins.json") + " is not valid JSON, so plugin skills, agents and hooks are not shown."; !hasProblem(inv, want) {
		t.Errorf("installed_plugins.json: %q", inv.Problems)
	}
	noLeak(t, inv)

	// An invalid settings.json: the plugin items and skill overrides vanish, and the screen is told.
	h4 := newTempHome(t)
	h4.write("cache/acme/skills/s/SKILL.md", skillFile("s"))
	h4.write(".claude/plugins/installed_plugins.json", `{"plugins": {"acme@market": [{"installPath": "`+h4.path("cache/acme")+`"}]}}`)
	h4.write(".claude/settings.json", "{ "+secretText)
	inv = Read(h4.roots())
	if item(inv, "s") != nil {
		t.Error("setup: the plugin skill should vanish with an invalid settings.json")
	}
	if want := h4.path(".claude/settings.json") + " is not valid JSON, so enabled plugins and skill overrides are not known."; !hasProblem(inv, want) {
		t.Errorf("settings.json: %q", inv.Problems)
	}
	noLeak(t, inv)

	// A valid or missing settings.json adds no such line.
	h5 := newTempHome(t)
	if inv := Read(h5.roots()); len(inv.Problems) != 0 {
		t.Errorf("empty home: %q", inv.Problems)
	}
}

// G-fix.14: hooks of a type other than command are counted in one line.
func TestHooksOfOtherTypesAreCounted(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/settings.json", `{"hooks": {
		"Stop": [{"hooks": [
			{"type": "command", "command": "echo shown"},
			{"type": "http", "url": "https://example.test/`+secretText+`"},
			{"type": "prompt", "prompt": "check"}]}],
		"PreToolUse": [{"matcher": "Edit", "hooks": [{"type": "mcp_tool", "server": "s", "tool": "t"}, {"type": "agent", "prompt": "p"}, 42, {"nothing": true}]}]}}`)
	inv := Read(h.roots())
	if len(inv.Hooks) != 1 || inv.Hooks[0].Command != "echo shown" {
		t.Errorf("hooks = %+v", inv.Hooks)
	}
	if want := "4 hooks of other types are not shown."; !hasProblem(inv, want) || len(inv.Problems) != 1 {
		t.Errorf("problems = %q", inv.Problems)
	}
	noLeak(t, inv)

	// One line over all files, singular for one.
	h.write(".claude/settings.json", `{"hooks": {"Stop": [{"hooks": [{"type": "http", "url": "u"}]}]}}`)
	h.write(".codex/hooks.json", `{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo c"}]}]}}`)
	inv = Read(h.roots())
	if want := "1 hook of another type is not shown."; !hasProblem(inv, want) || len(inv.Problems) != 1 {
		t.Errorf("problems = %q", inv.Problems)
	}
	h.write(".codex/hooks.json", `{"hooks": {"Stop": [{"hooks": [{"type": "http", "url": "u"}]}]}}`)
	if inv = Read(h.roots()); !hasProblem(inv, "2 hooks of other types are not shown.") {
		t.Errorf("problems over two CLIs = %q", inv.Problems)
	}

	// Command hooks only, or none: no line.
	h.write(".claude/settings.json", hookConfig("Stop", "echo a"))
	h.write(".codex/hooks.json", `{"hooks": {"Stop": [{"hooks": [{"command": 5}]}]}}`)
	if inv = Read(h.roots()); len(inv.Problems) != 0 {
		t.Errorf("no other types: %q", inv.Problems)
	}
}
