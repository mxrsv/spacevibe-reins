package mutate

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"sync/atomic"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/usage"
)

// Tests for the P1 follow-ups (G-fix.3 to G-fix.9, G-fix.16, G-fix.17). Each one fails on the Swift behavior it replaces.

func idOf(t *testing.T, r roots.Roots, name string, kind inventory.Kind, cli usage.CLI) string {
	t.Helper()
	for _, it := range inventory.Read(r).Items {
		if it.Name == name && it.Kind == kind && it.CLI == cli {
			return it.ID
		}
	}
	t.Fatalf("no %s %s", kind, name)
	return ""
}

// G-fix.3: a journal.json is a file anyone can edit; Undo must not move, write or remove anything outside the folders
// SpaceVibe manages, and refuses before it changes anything.
func TestUndoRefusesPathsOutsideTheManagedFolders(t *testing.T) {
	h := newCopy(t)
	r := h.r
	victim := h.write("outside/victim.txt", "secret")
	outsideDir := filepath.Dir(victim)
	trashed := h.write(".spacevibe/trash/1-aaaaaaaa/victim.txt", "saved")
	settings := h.path(".claude/settings.json")
	hook := ojson.Object(member("type", ojson.String("command")), member("command", ojson.String("echo x")))
	hookOp := func(kind, file string, restore ojson.Value) Op {
		return Op{ojson.Object(member("type", ojson.String(kind)), member("file", ojson.String(file)), member("event", ojson.String("Stop")),
			member("matcher", ojson.Null()), member("hook", hook), member("restore", restore))}
	}
	cases := map[string]Op{
		"created outside":              Created(outsideDir),
		"created with ..":              Created(h.path(".claude/skills/../../outside")),
		"created relative":             Created("skills/x"),
		"moved from outside":           Moved(victim, trashed),
		"moved to outside the trash":   Moved(h.path(".claude/skills/none"), victim),
		"moved to a managed non-trash": Moved(h.path(".claude/skills/none"), settings),
		"file-edited outside":          FileEdited(victim, true, trashed, strings.Repeat("0", 64)),
		"file-edited backup outside":   FileEdited(settings, true, victim, strings.Repeat("0", 64)),
		"link-removed outside":         LinkRemoved(victim, "x"),
		"hook-removed outside":         hookOp("hook-removed", victim, ojson.Null()),
		"hook restore outside":         hookOp("hook-added", settings, FileEdited(victim, true, trashed, strings.Repeat("0", 64)).JSON),
	}
	before := h.tree()
	for _, name := range slices.Sorted(mapsKeys(cases)) {
		entry := must(Record(r, name, []Op{cases[name]}))
		_, err := Undo(r, entry.ID)
		if m := wantErr(t, err, 400); m != outsideManagedMessage {
			t.Errorf("%s: message %q", name, m)
		}
	}
	for _, e := range historyOf(t, r) {
		if e.Undone {
			t.Errorf("%q was marked undone", e.Label)
		}
	}
	after := h.tree()
	for k, v := range before {
		if after[k] != v {
			t.Errorf("%s changed", k)
		}
	}
	if h.read("outside/victim.txt") != "secret" || exists(h.path("outside")) == false {
		t.Error("the file outside was touched")
	}
}

func mapsKeys[V any](m map[string]V) func(yield func(string) bool) {
	return func(yield func(string) bool) {
		for k := range m {
			if !yield(k) {
				return
			}
		}
	}
}

// G-fix.3: what the engine itself records must still undo: a dotfiles link (the journal holds the link target), a
// skills folder that is a link, and a rules edit in a project that discovery found.
func TestUndoStillAcceptsWhatTheEngineRecords(t *testing.T) {
	h := newCopy(t)
	projects := inventory.DiscoverProjects(h.r)
	if len(projects) == 0 {
		t.Fatal("the fixture has no project")
	}
	file := filepath.Join(projects[0], ".claude", "spacevibe-test-undo.json")
	entry := must(EditJSON(h.r, file, "Added", nil, addRule("Read")))
	must(Undo(h.r, entry.ID))
	if exists(file) {
		t.Error("the project file was not undone")
	}

	// A project file that discovery did not find is not ours to change.
	stranger := h.path("elsewhere/.claude/settings.local.json")
	entry = must(EditJSON(h.r, stranger, "Added", nil, addRule("Read")))
	_, err := Undo(h.r, entry.ID)
	wantErr(t, err, 400)
	if !exists(stranger) {
		t.Error("the stranger file was removed")
	}
}

// G-fix.5: a copy refuses a skill whose link points out of its folder, before it writes anything.
func TestCopySkillRefusesALinkOutOfItsFolder(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/leaky/SKILL.md", skillMd("leaky", "d"))
	h.write("outside/secret.txt", "secret")
	h.symlink(h.path("outside/secret.txt"), ".claude/skills/leaky/notes")
	_, err := CopyToOther(r, idOf(t, r, "leaky", inventory.KindSkill, inventory.Claude))
	if m := wantErr(t, err, 409); !strings.Contains(m, "points outside") {
		t.Errorf("message %q", m)
	}
	if exists(filepath.Join(r.Codex.Skills, "leaky")) || len(trashFiles(r)) != 0 || len(historyOf(t, r)) != 0 {
		t.Error("the refusal left something behind")
	}
}

// G-fix.5: files are created 0600 (a script keeps the owner's execute bit), folders 0700, nothing for group or other.
func TestCopyModes(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/modes/SKILL.md", skillMd("modes", "d"))
	h.write(".claude/skills/modes/scripts/run.sh", "#!/bin/sh\n")
	h.write(".claude/skills/modes/ref.txt", "ref")
	for p, m := range map[string]os.FileMode{"scripts/run.sh": 0o755, "ref.txt": 0o644, "SKILL.md": 0o664} {
		if err := os.Chmod(h.path(".claude/skills/modes/"+p), m); err != nil {
			t.Fatal(err)
		}
	}
	must(CopyToOther(r, idOf(t, r, "modes", inventory.KindSkill, inventory.Claude)))
	dest := filepath.Join(r.Codex.Skills, "modes")
	for p, want := range map[string]os.FileMode{"": 0o700, "scripts": 0o700, "scripts/run.sh": 0o700, "ref.txt": 0o600, "SKILL.md": 0o600} {
		if got := h.mode(filepath.Join(dest, p)); got != want {
			t.Errorf("%q mode %o, want %o", p, got, want)
		}
	}
	// Agents and new skills are 0600 too.
	must(AddAgent(r, []usage.CLI{inventory.Claude, inventory.Codex}, "agent-a", "d", "do it"))
	must(AddSkill(r, []usage.CLI{inventory.Claude}, "skill-a", "d", ""))
	for _, p := range []string{".claude/agents/agent-a.md", ".codex/agents/agent-a.toml", ".claude/skills/skill-a/SKILL.md"} {
		if got := h.mode(h.path(p)); got != 0o600 {
			t.Errorf("%s mode %o, want 600", p, got)
		}
	}
}

// G-fix.5: size caps. An agent file over 1 MiB and a skill file over 16 MiB are 413, and nothing is written.
func TestCopyCaps(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/agents/big.md", "---\nname: big\ndescription: d\n---\n"+strings.Repeat("x", maxAgentBytes))
	_, err := CopyToOther(r, idOf(t, r, "big", inventory.KindAgent, inventory.Claude))
	wantErr(t, err, 413)

	h.write(".claude/skills/heavy/SKILL.md", skillMd("heavy", "d"))
	heavy := h.write(".claude/skills/heavy/blob.bin", "")
	if err := os.Truncate(heavy, maxSkillFileBytes+1); err != nil {
		t.Fatal(err)
	}
	_, err = CopyToOther(r, idOf(t, r, "heavy", inventory.KindSkill, inventory.Claude))
	wantErr(t, err, 413)
	if exists(filepath.Join(r.Codex.Agents, "big.toml")) || exists(filepath.Join(r.Codex.Skills, "heavy")) || len(historyOf(t, r)) != 0 {
		t.Error("a refused copy wrote something")
	}
}

// G-fix.7: a repeated CLI is one CLI.
func TestDuplicateCLIsAreOne(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	twice := []usage.CLI{inventory.Claude, inventory.Claude}
	skill := must(AddSkill(r, twice, "dup", "d", ""))
	agent := must(AddAgent(r, twice, "dup-agent", "d", ""))
	hook := must(AddHook(r, twice, "Stop", nil, "echo once", nil))
	if skill.Label != "Added skill dup to Claude Code" || len(skill.Ops) != 1 || agent.Label != "Added agent dup-agent to Claude Code" || len(agent.Ops) != 1 ||
		hook.Label != "Added Stop hook to Claude Code" || len(hook.Ops) != 1 {
		t.Errorf("labels %q %q %q", skill.Label, agent.Label, hook.Label)
	}
}

// G-fix.7: a rollback sends exactly what the change created to the trash, never a path somebody else made after the check.
func TestRollbackNeverTrashesAPathItDidNotCreate(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	foreign := h.path(".codex/skills/raced")
	h.write(".codex/skills/raced/SKILL.md", "theirs")
	mine := h.path(".claude/skills/raced")
	_, err := locked(r, func(tx *Tx) ([]Op, error) {
		return tx.createAll([]usage.CLI{inventory.Claude, inventory.Codex}, func(cli usage.CLI) (createPlan, error) {
			// The "does it exist" check passed for both, then the second folder appeared: the write meets it.
			if cli == inventory.Claude {
				return createPlan{path: mine, write: func() (bool, error) { return writeSkill(mine, "mine") }}, nil
			}
			return createPlan{path: foreign, write: func() (bool, error) { return writeSkill(foreign, "mine") }}, nil
		})
	})
	wantErr(t, err, 409)
	if h.read(".codex/skills/raced/SKILL.md") != "theirs" || exists(mine) {
		t.Error("their folder changed, or the one this change made is still there")
	}
	if files := trashFiles(r); len(files) != 1 || !strings.HasSuffix(files[0], "/raced") {
		t.Errorf("trash %v", files)
	}
}

// G-fix.7: a copy that fails after it made the top folder leaves nothing half-made and unrecorded.
func TestFailedCopyIsRolledBack(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads everything")
	}
	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/half/SKILL.md", skillMd("half", "d"))
	locked := h.write(".claude/skills/half/zz-locked.txt", "x")
	if err := os.Chmod(locked, 0); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(locked, 0o644)
	_, err := CopyToOther(r, idOf(t, r, "half", inventory.KindSkill, inventory.Claude))
	wantErr(t, err, 409)
	if exists(filepath.Join(r.Codex.Skills, "half")) || len(historyOf(t, r)) != 0 {
		t.Error("a half-made copy is left, or an entry was recorded")
	}
	if len(trashFiles(r)) != 1 {
		t.Errorf("the partial copy should be in the trash: %v", trashFiles(r))
	}
}

// G-fix.9: when an undo fails part way and a put-back fails too, the error says the entry is partly undone, and the
// failure that started it is still in the chain.
func TestUndoPutBackFailureIsReported(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	made := filepath.Dir(h.write(".claude/made/file.txt", "keep"))
	gone := h.path(".claude/work/gone.txt") // not there, and the saved copy is not there either: the second op refuses
	entry := must(Record(r, "Two ops", []Op{Moved(gone, h.path(".spacevibe/trash/9-zzzzzzzz/gone.txt")), Created(made)}))

	var calls atomic.Int32
	diskTrouble := errors.New("disk trouble") // fsx keeps only its reason text in the 500 it returns
	old := renameFile
	renameFile = func(from, to string) error {
		if calls.Add(1) == 1 {
			return os.Rename(from, to) // the created folder goes to the trash
		}
		return diskTrouble // ... and cannot be put back
	}
	defer func() { renameFile = old }()

	_, err := Undo(r, entry.ID)
	if m := wantErr(t, err, 500); m != PartlyUndoneMessage {
		t.Errorf("message %q", m)
	}
	if !errors.Is(err, coreerr.NewStatus("The saved copy of "+gone+" is gone, so it was left alone.", 409)) {
		t.Errorf("the original refusal is not in the chain: %v", err)
	}
	if !chainHas(err, func(e error) bool {
		ce, ok := e.(coreerr.Error)
		return ok && strings.Contains(ce.Message, diskTrouble.Error())
	}) {
		t.Errorf("the failed put-back is not in the chain: %v", err)
	}
	if historyOf(t, r)[0].Undone {
		t.Error("a partly undone entry was marked undone")
	}
}

// chainHas walks err's whole chain, joins included.
func chainHas(err error, match func(error) bool) bool {
	if err == nil {
		return false
	}
	if match(err) {
		return true
	}
	switch u := err.(type) {
	case interface{ Unwrap() []error }:
		for _, e := range u.Unwrap() {
			if chainHas(e, match) {
				return true
			}
		}
	case interface{ Unwrap() error }:
		return chainHas(u.Unwrap(), match)
	}
	return false
}

// G-fix.8: History is an error for a journal that is not an array, through the service too, never an empty list.
func TestServiceHistoryReportsACorruptJournal(t *testing.T) {
	h := newHome(t)
	svc := NewService(h.roots())
	res, err := svc.History(context.Background())
	if err != nil || res.Entries == nil || len(res.Entries) != 0 {
		t.Fatalf("empty history: %+v, %v", res, err)
	}
	h.write(".spacevibe/journal.json", "[1, 2")
	_, err = svc.History(context.Background())
	wantErr(t, err, 409)
}

// The service speaks the wire shape of docs/internals/core-protocol.md and starts nothing for a cancelled request.
func TestServiceWireShape(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/skills/wire/SKILL.md", skillMd("wire", "d"))
	svc := NewService(r)
	res, err := svc.CopyToOther(context.Background(), IDParams{ID: idOf(t, r, "wire", inventory.KindSkill, inventory.Claude)})
	if err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(res)
	var shape map[string]map[string]any
	if err := json.Unmarshal(data, &shape); err != nil {
		t.Fatal(err)
	}
	entry := shape["entry"]
	keys := make([]string, 0)
	for k := range entry {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	if !slices.Equal(keys, []string{"at", "count", "id", "label", "undone"}) || entry["label"] != "Copied skill wire to Codex" || entry["count"] != float64(1) || entry["undone"] != false {
		t.Errorf("shape %s", data)
	}
	undo, err := svc.Undo(context.Background(), IDParams{ID: res.Entry.ID})
	if err != nil || undo.Label != "Copied skill wire to Codex" {
		t.Errorf("undo %+v, %v", undo, err)
	}
	if _, err := svc.RemoveDeadHooks(context.Background(), CLIParams{CLI: "gemini"}); statusOf(err) != 400 {
		t.Errorf("unknown cli: %v", err)
	}
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := svc.Undo(cancelled, IDParams{ID: res.Entry.ID}); !errors.Is(err, context.Canceled) {
		t.Errorf("cancelled: %v", err)
	}
}

// G-fix.16: AddHook is not an RPC method. Only the five methods of the protocol are on the service.
func TestServiceHasOnlyTheProtocolMethods(t *testing.T) {
	typ := reflect.TypeOf(&Service{})
	var got []string
	for i := 0; i < typ.NumMethod(); i++ {
		got = append(got, typ.Method(i).Name)
	}
	want := []string{"CopyToOther", "History", "RemoveDeadHooks", "RemoveItem", "Undo"}
	if !slices.Equal(got, want) {
		t.Errorf("service methods %v, want %v", got, want)
	}
}

// G-fix.17: copying an agent that has no instructions is refused (Codex rejects an empty developer_instructions), after
// the "already has an agent" check; nothing is written.
func TestCopyAgentWithoutInstructionsIsRefused(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	h.write(".claude/agents/hollow.md", "---\nname: hollow\ndescription: Does nothing\n---\n\n   \n")
	before := len(historyOf(t, r))
	_, err := CopyToOther(r, idOf(t, r, "hollow", inventory.KindAgent, inventory.Claude))
	if m := wantErr(t, err, 409); !strings.Contains(m, "no instructions") {
		t.Errorf("message %q", m)
	}
	if exists(filepath.Join(r.Codex.Agents, "hollow.toml")) || len(historyOf(t, r)) != before {
		t.Error("a refused copy wrote something")
	}
	// The existing-file check comes first.
	h.write(".codex/agents/hollow.toml", "name = \"hollow\"\n")
	_, err = CopyToOther(r, idOf(t, r, "hollow", inventory.KindAgent, inventory.Claude))
	if m := wantErr(t, err, 409); !strings.Contains(m, "already has an agent") {
		t.Errorf("message %q", m)
	}
	// Adding an agent with no instructions by hand stays allowed (the golden does it).
	if _, err := AddAgent(r, []usage.CLI{inventory.Claude}, "plain", "d", ""); err != nil {
		t.Error(err)
	}
}

// G-fix.17: U+007F is escaped in a TOML basic string; JSON.stringify leaves it raw and TOML forbids it.
func TestTomlEscapesDelete(t *testing.T) {
	h := newHome(t)
	r := h.roots()
	instructions := "before\x7fafter"
	must(AddAgent(r, []usage.CLI{inventory.Codex}, "del", "desc\x7f", instructions))
	text := h.read(".codex/agents/del.toml")
	if strings.ContainsRune(text, 0x7f) || !strings.Contains(text, `before\u007fafter`) || !strings.Contains(text, `desc\u007f`) {
		t.Errorf("toml %q", text)
	}
	if tomlInstructions(text) != instructions || tomlDescription(text) != "desc\x7f" {
		t.Errorf("round trip: %q, %q", tomlInstructions(text), tomlDescription(text))
	}
	// The markdown header keeps JSON quoting, which YAML reads.
	if got := quote("a\x7fb"); got != "\"a\x7fb\"" {
		t.Errorf("quote %q", got)
	}
}
