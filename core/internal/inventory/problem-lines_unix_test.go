//go:build unix

package inventory

import (
	"os"
	"testing"
)

// chmod000 makes the file unreadable for the test; skipped for root, which ignores file permissions.
func chmod000(t *testing.T, path string) {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Skip("root ignores file permissions")
	}
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(path, 0o644) })
}

// G-fix.13: a SKILL.md or agent file that is there but cannot be read is a problem line, not a silent skip; a skill
// folder with no SKILL.md at all stays quiet.
func TestUnreadableSkillAndAgentAreReported(t *testing.T) {
	h := newTempHome(t)
	skill := h.write(".claude/skills/locked/SKILL.md", skillFile("locked"))
	agent := h.write(".claude/agents/locked.md", "---\nname: locked\n---\n")
	tomlAgent := h.write(".codex/agents/locked.toml", "name = \"locked\"\n")
	h.write(".claude/skills/ok/SKILL.md", skillFile("ok"))
	h.write(".claude/skills/not-a-skill/README.md", "x")
	chmod000(t, skill)
	chmod000(t, agent)
	chmod000(t, tomlAgent)

	inv := Read(h.roots())
	for _, want := range []string{
		skill + " cannot be read, so this skill is not shown.",
		agent + " cannot be read, so this agent is not shown.",
		tomlAgent + " cannot be read, so this agent is not shown.",
	} {
		if !hasProblem(inv, want) {
			t.Errorf("missing %q in %q", want, inv.Problems)
		}
	}
	if len(inv.Problems) != 3 {
		t.Errorf("problems = %q", inv.Problems)
	}
	if item(inv, "locked") != nil || item(inv, "ok") == nil {
		t.Error("the unreadable item is not listed and the readable one is")
	}
}

// G-fix.13: a plugin hooks.json that cannot be opened.
func TestUnreadablePluginHooksFileIsReported(t *testing.T) {
	h := newTempHome(t)
	hooks := h.write("cache/acme/hooks/hooks.json", hookConfig("Stop", "echo x"))
	h.write(".claude/plugins/installed_plugins.json", `{"plugins": {"acme@market": [{"installPath": "`+h.path("cache/acme")+`"}]}}`)
	h.write(".claude/settings.json", `{"enabledPlugins": {"acme@market": true}}`)
	chmod000(t, hooks)
	inv := Read(h.roots())
	if want := hooks + " cannot be read, so the hooks of the plugin acme are not shown."; !hasProblem(inv, want) {
		t.Errorf("problems = %q", inv.Problems)
	}
}
