package mutate

import (
	"context"
	"errors"
	"os"
	"reflect"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/roots"
)

func TestWritersMatchRegistry(t *testing.T) {
	if err := writers.Check(); err != nil {
		t.Fatal(err)
	}
}

// MC-T3: a write naming a CLI SpaceVibe does not write (Gemini CLI has no mutate concept) or an id the registry does
// not know is refused and writes nothing. The old cliRoots sent every id that was not Claude Code to Codex's folders,
// so these calls created ~/.codex/skills/<name> and ~/.codex/agents/<name>.toml.
func TestWriteToAnUnwrittenCLIIsRefused(t *testing.T) {
	cases := []struct {
		id   clis.ID
		want error
	}{{clis.Gemini, clis.ErrConceptAbsent}, {"nope", clis.ErrUnknownCLI}}
	for _, c := range cases {
		h := newHome(t)
		h.write(".codex/config.toml", "")
		h.write(".claude/settings.json", "{}")
		r := h.roots()
		if _, err := AddSkill(r, []clis.ID{c.id}, "stray", "Synthetic skill", ""); !errors.Is(err, c.want) {
			t.Errorf("AddSkill(%s) = %v, want %v", c.id, err, c.want)
		}
		if _, err := AddAgent(r, []clis.ID{c.id}, "stray", "Synthetic agent", "Do it."); !errors.Is(err, c.want) {
			t.Errorf("AddAgent(%s) = %v, want %v", c.id, err, c.want)
		}
		if _, err := AddHook(r, []clis.ID{c.id}, "Stop", nil, "true", nil); !errors.Is(err, c.want) {
			t.Errorf("AddHook(%s) = %v, want %v", c.id, err, c.want)
		}
		for _, rel := range []string{".codex/skills/stray", ".codex/agents/stray.toml", ".claude/skills/stray", ".codex/hooks.json"} {
			if _, err := os.Lstat(h.path(rel)); !errors.Is(err, os.ErrNotExist) {
				t.Errorf("%s: %s was written (err %v)", c.id, rel, err)
			}
		}
	}
}

// loadout.removeDeadHooks accepts exactly the CLIs with a writer, and words the refusal from the registry.
func TestRemoveDeadHooksAcceptsOnlyWrittenCLIs(t *testing.T) {
	h := newHome(t)
	s := NewService(h.roots())
	for _, id := range []clis.ID{clis.Gemini, "nope", ""} {
		_, err := s.RemoveDeadHooks(context.Background(), CLIParams{CLI: id})
		e, ok := coreerr.As(err)
		if !ok || e.Message != "cli must be claude or codex." {
			t.Errorf("%q: err = %v", id, err)
		}
	}
	for _, id := range clis.IDsWith(clis.Mutate) {
		_, err := s.RemoveDeadHooks(context.Background(), CLIParams{CLI: id})
		if e, ok := coreerr.As(err); !ok || strings.HasPrefix(e.Message, "cli must be") {
			t.Errorf("%s was refused as a CLI: %v", id, err)
		}
	}
}

// copyToTheOther copies id to the first other CLI SpaceVibe writes: the target every copy had before the request named
// one, which the golden scenarios and the older tests assume.
func copyToTheOther(r roots.Roots, id string) (Entry, error) {
	source, _, _ := strings.Cut(id, ":")
	for _, target := range clis.IDsWith(clis.Mutate) {
		if target != clis.ID(source) {
			return CopyTo(r, id, target)
		}
	}
	panic("test bug: no other CLI to copy to")
}

// MC-R8: the copy names its target. An unknown or empty target, a CLI SpaceVibe does not write and the item's own CLI
// are refused with a sentence before anything is written; the first two keep the registry error behind the sentence.
func TestCopyNeedsAnExplicitTarget(t *testing.T) {
	h := newCopy(t)
	skill := h.item("tdd", inventory.KindSkill, clis.Claude)
	cases := []struct {
		target  clis.ID
		message string
		cause   error
	}{
		{"nope", "target must be claude or codex.", clis.ErrUnknownCLI},
		{"", "target must be claude or codex.", clis.ErrUnknownCLI},
		{clis.Gemini, "SpaceVibe does not write Gemini CLI, so nothing was copied.", clis.ErrConceptAbsent},
		{clis.Claude, "This skill is already in Claude Code. Pick another CLI to copy it to.", nil},
	}
	before := h.tree()
	for _, c := range cases {
		_, err := CopyTo(h.r, skill.ID, c.target)
		if m := wantErr(t, err, 400); m != c.message {
			t.Errorf("%q: message %q", c.target, m)
		}
		if c.cause != nil && !errors.Is(err, c.cause) {
			t.Errorf("%q: %v does not wrap %v", c.target, err, c.cause)
		}
	}
	if after := h.tree(); !reflect.DeepEqual(before, after) {
		t.Error("a refused copy changed the tree")
	}
	if e := must(CopyTo(h.r, skill.ID, clis.Codex)); e.Label != "Copied skill tdd to Codex" {
		t.Errorf("label %q", e.Label)
	}
}

// withKinds gives cli another per-kind declaration for one test.
func withKinds(t *testing.T, cli clis.ID, kinds inventory.Kinds) {
	t.Helper()
	saved := kindsOf
	kindsOf = func(id clis.ID) (inventory.Kinds, error) {
		if id == cli {
			return kinds, nil
		}
		return saved(id)
	}
	t.Cleanup(func() { kindsOf = saved })
}

// MC-R8, MC29: a copy goes only into a CLI that writes the kind in the same copy format. A target whose format
// differs, whose kind is read-only, or that lacks the kind is refused, and nothing is converted or written.
func TestCopyRefusesAnotherFormatOrAMissingKind(t *testing.T) {
	cases := []struct {
		name    string
		skill   inventory.KindSupport
		status  int
		message string
	}{
		{"other format", inventory.KindSupport{Support: inventory.SupportFull, Runs: inventory.RunsCounted, CopyFormat: "otherSkill"}, 409,
			"Codex reads another skill format, so this skill cannot be copied to it."},
		{"no format", inventory.KindSupport{Support: inventory.SupportFull, Runs: inventory.RunsCounted}, 409,
			"Codex reads another skill format, so this skill cannot be copied to it."},
		{"read-only", inventory.KindSupport{Support: inventory.SupportReadOnly, Runs: inventory.RunsCounted, CopyFormat: inventory.CopySkillFolder}, 403,
			"SpaceVibe only shows the skills of Codex, so nothing was changed."},
		{"absent", inventory.KindSupport{Support: inventory.SupportAbsent}, 409, "Codex has no skills, so nothing was changed."},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			h := newCopy(t)
			skill := h.item("tdd", inventory.KindSkill, clis.Claude)
			kinds, err := inventory.KindsOf(clis.Codex)
			if err != nil {
				t.Fatal(err)
			}
			changed := inventory.Kinds{}
			for k, v := range kinds {
				changed[k] = v
			}
			changed[inventory.KindSkill] = c.skill
			withKinds(t, clis.Codex, changed)
			before := h.tree()
			_, err = CopyTo(h.r, skill.ID, clis.Codex)
			if m := wantErr(t, err, c.status); m != c.message {
				t.Errorf("message %q", m)
			}
			if after := h.tree(); !reflect.DeepEqual(before, after) {
				t.Error("a refused copy changed the tree")
			}
		})
	}
}

// The subagent-tools fact the shell words a copy with comes from the writer that makes the copy: a writer that says a
// tool-less agent gets every tool must really write no tools line.
func TestAgentWithoutToolsWritesNoToolsLine(t *testing.T) {
	for _, w := range writers.InOrder() {
		_, text := w.Adapter.agentFile("name", "description", "Do it.")
		if w.Adapter.agentWithoutToolsGetsEveryTool() && strings.Contains(text, "tools") {
			t.Errorf("%s writes a tools line but claims a tool-less agent:\n%s", w.ID, text)
		}
	}
	if !AgentWithoutToolsGetsEveryTool(clis.Claude) || AgentWithoutToolsGetsEveryTool(clis.Codex) || AgentWithoutToolsGetsEveryTool(clis.Gemini) {
		t.Error("AgentWithoutToolsGetsEveryTool: want true for Claude Code only")
	}
}
