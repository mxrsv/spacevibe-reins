package mutate

import (
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/usage"
)

// WriteGuardTests.swift. The three tests that go through RulesStore (a project .claude that is a link, a settings file
// that is a link, the controls that still work) belong to the rules package (G2.4); the other eight are here.

func (s sandbox) trashSlots() []string { return names(trashDir(s.r)) }

func (s sandbox) journalEmpty() bool {
	h, err := History(s.r)
	return err == nil && len(h) == 0
}

// withMode sets a mode for the body and puts the old one back, so the temp folder can be deleted.
func withMode(t *testing.T, mode os.FileMode, path string, body func()) {
	t.Helper()
	old := mustMode(t, path)
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(path, old)
	body()
}

func mustMode(t *testing.T, path string) os.FileMode {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	return info.Mode().Perm()
}

func victimItem(path string) inventory.Item {
	return inventory.Item{
		ID: "claude:skill:user:victim", CLI: inventory.Claude, Kind: inventory.KindSkill, Name: "victim", Entry: "victim",
		Owner: "user", Path: path, File: path + "/SKILL.md", Removable: true, Scope: inventory.ScopeGlobal,
	}
}

// Swift: WriteGuardTests.swift "removing a skill whose path goes out of the CLI folder is 403 and changes nothing"
func TestRemoveOutsideCLIFolder(t *testing.T) {
	sb := newSandbox(t)
	victim := filepath.Dir(sb.write("outside/victim/SKILL.md", "---\nname: victim\n---\n"))
	skills := sb.r.Claude.Skills
	sb.symlink(filepath.Dir(victim), ".claude/skills/hop")
	// A link in the middle of the path (lexically inside the folder), and a `..` path (lexically outside).
	for _, path := range []string{skills + "/hop/victim", skills + "/../../outside/victim"} {
		_, err := locked(sb.r, func(tx *Tx) (Entry, error) { return tx.removeFile(victimItem(path)) })
		if m := wantErr(t, err, 403); m != "Refusing a path outside the CLI folder." {
			t.Errorf("%s: %q", path, m)
		}
	}
	if !exists(filepath.Join(victim, "SKILL.md")) || len(names(filepath.Dir(victim))) != 1 || !sb.journalEmpty() || len(sb.trashSlots()) != 0 {
		t.Error("something changed")
	}
}

// Swift: WriteGuardTests.swift "a skills folder that is itself a link (dotfiles) still lets its skills be removed"
func TestRemoveThroughLinkedSkillsFolder(t *testing.T) {
	sb := newSandbox(t)
	sb.write("dotfiles/skills/mine/SKILL.md", "---\nname: mine\ndescription: d\n---\n")
	sb.symlink(sb.path("dotfiles/skills"), ".claude/skills")
	var id string
	for _, it := range inventory.Read(sb.r).Items {
		if it.Name == "mine" {
			id = it.ID
		}
	}
	entry := must(RemoveItem(sb.r, id))
	if entry.Label != "Removed skill mine from Claude Code" || exists(sb.path("dotfiles/skills/mine")) {
		t.Errorf("label %q", entry.Label)
	}
	must(Undo(sb.r, entry.ID))
	if !exists(sb.path("dotfiles/skills/mine/SKILL.md")) {
		t.Error("the skill did not come back")
	}
}

// Swift: WriteGuardTests.swift "addSkill into both CLIs: when the second folder cannot be written the first skill is gone and nothing is recorded"
func TestCreateAllRollback(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root ignores folder permissions")
	}
	sb := newSandbox(t)
	for _, d := range []string{sb.r.Claude.Skills, sb.r.Codex.Skills} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	var err error
	withMode(t, 0o500, sb.r.Codex.Skills, func() {
		_, err = AddSkill(sb.r, []usage.CLI{inventory.Claude, inventory.Codex}, "both", "when needed", "")
	})
	wantErr(t, err, 500)
	if exists(filepath.Join(sb.r.Claude.Skills, "both")) {
		t.Error("the first CLI's skill is still there")
	}
	if len(names(sb.r.Codex.Skills)) != 0 || !sb.journalEmpty() {
		t.Error("the second folder or the journal changed")
	}
	// The skill went to the app trash instead of being deleted; the codex path that never existed made no slot.
	if len(sb.trashSlots()) != 1 {
		t.Errorf("trash slots %v", sb.trashSlots())
	}
}

// Swift: WriteGuardTests.swift "a settings path that is a folder is refused (409): no temp file, no journal entry, no trash slot"
func TestSettingsPathIsFolder(t *testing.T) {
	sb := newSandbox(t)
	if err := os.MkdirAll(sb.r.Claude.HookFile, 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := EditJSON(sb.r, sb.r.Claude.HookFile, "Added", nil, func(d *ojson.Document) (*ojson.Document, error) {
		return d.Set(ojson.Path("model"), ojson.String("x"))
	})
	if m := wantErr(t, err, 409); !strings.Contains(m, "not a regular file") {
		t.Errorf("message %q", m)
	}
	if len(names(sb.r.Claude.HookFile)) != 0 || len(sb.stray()) != 0 || !sb.journalEmpty() || len(sb.trashSlots()) != 0 {
		t.Error("something was left behind")
	}
}

// Swift: WriteGuardTests.swift "a read-only folder: 500, file untouched, no journal entry, no temp file, no trash slot"
func TestReadOnlyFolder(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root ignores folder permissions")
	}
	sb := newSandbox(t)
	settings := sb.write(".claude/settings.json", "{\n  \"model\": \"keep\"\n}\n")
	folder := filepath.Dir(settings)
	for _, existing := range []bool{true, false} {
		file := settings
		if !existing {
			file = filepath.Join(folder, "settings.local.json")
		}
		var err error
		withMode(t, 0o500, folder, func() {
			_, err = EditJSON(sb.r, file, "Added", nil, func(d *ojson.Document) (*ojson.Document, error) {
				return d.Set(ojson.Path("model"), ojson.String("changed"))
			})
		})
		if m := wantErr(t, err, 500); strings.Contains(m, "keep") {
			t.Errorf("existing %v: %q", existing, m)
		}
	}
	if sb.bytes() != "{\n  \"model\": \"keep\"\n}\n" || len(names(folder)) != 1 || !sb.journalEmpty() || len(sb.trashSlots()) != 0 {
		t.Errorf("files %v slots %v", names(folder), sb.trashSlots())
	}
}

// hookTimeout adds a Stop hook, reads the hook object back and undoes the entry.
func hookTimeout(t *testing.T, sb sandbox, timeout *float64) ojson.Value {
	t.Helper()
	entry := must(AddHook(sb.r, []usage.CLI{inventory.Claude}, "Stop", nil, "echo t", timeout))
	doc := must(ojson.ParseString(sb.bytes(sb.r.Claude.HookFile)))
	must(Undo(sb.r, entry.ID))
	hooks, _ := doc.Get(ojson.Key("hooks"), ojson.Key("Stop"))
	group, _ := hooks.Element(0)
	inner, _ := group.Member("hooks")
	hook, _ := inner.Element(0)
	return hook
}

func f(v float64) *float64 { return &v }

// Swift: WriteGuardTests.swift "hook timeout: 0 and nil leave the key out (as Node does), whole numbers have no decimals, 2.5 stays 2.5"
func TestHookTimeoutFormats(t *testing.T) {
	sb := newSandbox(t)
	for _, timeout := range []*float64{nil, f(0), f(math.Copysign(0, -1))} {
		if _, ok := hookTimeout(t, sb, timeout).Member("timeout"); ok {
			t.Errorf("timeout %v wrote a key", timeout)
		}
	}
	for _, c := range []struct {
		in   float64
		want string
	}{{30, "30"}, {2.5, "2.5"}, {0.25, "0.25"}} {
		v, _ := hookTimeout(t, sb, f(c.in)).Member("timeout")
		if got, _ := v.NumberText(); got != c.want {
			t.Errorf("timeout %v wrote %q, want %q", c.in, got, c.want)
		}
	}
}

// Swift: WriteGuardTests.swift "hook timeout: nan and infinity are refused (400) and nothing is written"
func TestHookTimeoutNonFinite(t *testing.T) {
	sb := newSandbox(t)
	for _, v := range []float64{math.NaN(), math.Inf(1), math.Inf(-1)} {
		_, err := AddHook(sb.r, []usage.CLI{inventory.Claude}, "Stop", nil, "echo t", f(v))
		wantErr(t, err, 400)
	}
	if exists(sb.r.Claude.HookFile) || !sb.journalEmpty() {
		t.Error("something was written")
	}
}

// Swift: WriteGuardTests.swift "undo after a hand edit, on a hook file the same entry created: the hook goes, the hand edit stays"
func TestUndoHookFileCreatedBySameEntryAfterHandEdit(t *testing.T) {
	sb := newSandbox(t)
	file := sb.r.Claude.HookFile
	if exists(file) {
		t.Fatal("hook file exists")
	}
	five := 5.0
	entry := must(AddHook(sb.r, []usage.CLI{inventory.Claude}, "Stop", nil, "echo made", &five))
	restore, _ := entry.Ops[0].JSON.Member("restore")
	if existed, _ := restore.Member("existed"); existed.Kind() != ojson.KindBool {
		t.Fatal("no restore data")
	} else if b, _ := existed.BoolValue(); b {
		t.Error("the entry should have created the file")
	}
	edited := must(must(ojson.ParseString(sb.bytes(file))).Set(ojson.Path("model"), ojson.String("by-hand")))
	sb.write(".claude/settings.json", edited.Text())

	must(Undo(sb.r, entry.ID))
	doc := must(ojson.ParseString(sb.bytes(file)))
	model, _ := doc.Get(ojson.Key("model"))
	for _, hk := range inventory.Read(sb.r).Hooks {
		if hk.Command == "echo made" {
			t.Error("the hook is still there")
		}
	}
	if !valueIs(model, "by-hand") || !historyOf(t, sb.r)[0].Undone || len(sb.stray()) != 0 {
		t.Error("the hand edit is gone, or the entry is not marked undone, or a temp file is left")
	}
}
