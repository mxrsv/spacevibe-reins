package mutate

import (
	"os"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/inventory"
)

// installCodex makes the folder a copy to Codex needs; a copy never creates it (GW5).
func (h tempHome) installCodex() {
	h.t.Helper()
	if err := os.MkdirAll(h.path(".codex"), 0o755); err != nil {
		h.t.Fatal(err)
	}
}

// M5: a skill copy is named after its folder, so a display name like "PDF Tools" no longer fails the copy.
func TestCopySkillTakesTheFolderName(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/pdf-tools/SKILL.md", skillMd("PDF Tools", "d"))
	h.installCodex()
	e := must(CopyToOther(r, idOf(t, r, "PDF Tools", inventory.KindSkill, inventory.Claude)))
	if e.Label != "Copied skill pdf-tools to Codex" || !exists(h.path(".codex/skills/pdf-tools/SKILL.md")) {
		t.Errorf("label %q", e.Label)
	}
}

// M5: a subagent whose name cannot be a file name is a 409 that names it.
func TestCopyAgentWithAnUnwritableNameIsRefused(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/agents/reviewer.md", "---\nname: Code_Reviewer\ndescription: d\n---\nReview it.\n")
	h.installCodex()
	_, err := CopyToOther(r, idOf(t, r, "Code_Reviewer", inventory.KindAgent, inventory.Claude))
	if m := wantErr(t, err, 409); !strings.Contains(m, "Code_Reviewer") {
		t.Errorf("message %q does not name the agent", m)
	}
	if exists(r.Codex.Agents) || len(historyOf(t, r)) != 0 {
		t.Error("the refusal left something behind")
	}
}

// GW5: with no Codex folder the copy is a 409 and creates nothing, not even the folder.
func TestCopyRefusesACLIThatIsNotInstalled(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/tdd/SKILL.md", skillMd("tdd", "d"))
	_, err := CopyToOther(r, idOf(t, r, "tdd", inventory.KindSkill, inventory.Claude))
	if m := wantErr(t, err, 409); m != "Codex is not installed on this Mac, so nothing was copied." {
		t.Errorf("message %q", m)
	}
	if exists(r.Codex.Root) || len(historyOf(t, r)) != 0 {
		t.Error("the refusal created something")
	}
}

// A skill whose FOLDER name cannot be a file name is a 409 that names the folder, not the display name.
func TestCopySkillWithAnUnwritableFolderNameNamesTheFolder(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/My_Skill/SKILL.md", skillMd("my-skill", "d"))
	h.installCodex()
	_, err := CopyToOther(r, idOf(t, r, "my-skill", inventory.KindSkill, inventory.Claude))
	if m := wantErr(t, err, 409); !strings.Contains(m, "My_Skill") {
		t.Errorf("message %q does not name the folder", m)
	}
	if exists(r.Codex.Skills) || len(historyOf(t, r)) != 0 {
		t.Error("the refusal left something behind")
	}
}
