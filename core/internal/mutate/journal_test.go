package mutate

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
)

// The paths of these vectors sit under a CLI folder (.claude/...) where Swift used the home folder itself: Undo now
// refuses a path outside the folders SpaceVibe manages (G-fix.3), so the ported inputs moved under a root. Nothing else
// about the vectors changed.

func labelsOf(h []EntryRef) []string {
	out := make([]string, len(h))
	for i, e := range h {
		out[i] = e.Label
	}
	return out
}

// Swift: JournalTests.swift "record writes the Node layout: newest first, key order, lowercase id, ms timestamp, mode 0600"
func TestRecordLayout(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	first := must(Record(r, "first", []Op{Created("/x/one")}))
	second := must(Record(r, "second", nil))

	if first.ID != strings.ToLower(first.ID) || len(first.ID) != 36 {
		t.Errorf("id %q", first.ID)
	}
	if !regexp.MustCompile(`^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$`).MatchString(first.At) {
		t.Errorf("at %q", first.At)
	}
	h := historyOf(t, r)
	if !slices.Equal(labelsOf(h), []string{"second", "first"}) || h[0].Count != 0 || h[1].Count != 1 || h[0].Undone || h[1].Undone {
		t.Errorf("history %+v", h)
	}
	text := home.read(".spacevibe/journal.json")
	prefix := "[\n  {\n    \"id\": \"" + second.ID + "\",\n    \"at\": \"" + second.At + "\",\n    \"label\": \"second\",\n    \"ops\": []\n  },"
	if !strings.HasPrefix(text, prefix) {
		t.Errorf("journal text starts %q", text[:min(len(text), 160)])
	}
	if strings.Contains(text, "undone") || strings.HasSuffix(text, "\n") {
		t.Errorf("undone or trailing newline in %q", text)
	}
	var parsed []any
	if err := json.Unmarshal([]byte(text), &parsed); err != nil || len(parsed) != 2 {
		t.Errorf("parsed %d entries, %v", len(parsed), err)
	}
	if m := home.mode(home.path(".spacevibe/journal.json")); m != 0o600 {
		t.Errorf("journal mode %o", m)
	}
	if m := home.mode(home.path(".spacevibe/trash")); m != 0o700 {
		t.Errorf("trash mode %o", m)
	}
}

// Swift: JournalTests.swift "keeps at most 200 entries"
func TestJournalKeepsTwoHundred(t *testing.T) {
	r := newHome(t).roots()
	for i := 0; i < 205; i++ {
		must(Record(r, "entry "+itoa(i), nil))
	}
	h := historyOf(t, r)
	if len(h) != 200 || h[0].Label != "entry 204" {
		t.Errorf("%d entries, first %q", len(h), h[0].Label)
	}
}

// recentDay is today's date: journal entries older than JournalMaxAge are dropped, so a fixture needs a current one.
func recentDay() string { return time.Now().UTC().Format("2006-01-02") }

const nodeJournal = `[
  {
    "id": "e271c1e3-dfc2-4e9f-9d14-ba967210bee5",
    "at": "2026-11-02T16:31:08.528Z",
    "label": "Added allow rule Read (global)",
    "ops": [
      {
        "type": "file-edited",
        "file": "SETTINGS",
        "existed": true,
        "backup": "BACKUP",
        "after": "e6435d1aa4741b10a9f7a2363778ee376b5a70c5905ff4d1fc6827b82d01f110"
      },
      {
        "type": "created",
        "path": "CREATED"
      }
    ]
  },
  {
    "id": "11111111-2222-3333-4444-555555555555",
    "at": "2026-11-02T16:00:00.000Z",
    "label": "Added Stop hook to Claude Code",
    "undone": true,
    "ops": [
      {
        "type": "hook-added",
        "file": "SETTINGS",
        "event": "Stop",
        "matcher": null,
        "hook": {
          "type": "command",
          "command": "echo",
          "timeout": 5
        }
      }
    ]
  },
  {
    "id": "99999999-2222-3333-4444-555555555555",
    "at": "2026-11-02T15:00:00.000Z",
    "label": "Removed Stop hook from Claude Code",
    "ops": [
      { "type": "hook-removed", "file": "SETTINGS", "event": "Stop", "matcher": null, "hook": { "type": "command", "command": "echo", "timeout": 5 } }
    ]
  }
]`

// Swift: JournalTests.swift "reads a journal written by the Node core, undoes an entry, refuses one already undone (409), and keeps foreign ops intact"
func TestReadsNodeJournal(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	settings := home.write(".claude/settings.json", "{\"model\":\"y\"}\n")
	backup := home.write(".spacevibe/trash/1793637068527-ff71479b/settings.json", "{\"model\":\"x\"}\n")
	created := home.write(".claude/skills/new/SKILL.md", "---\nname: new\n---\n")
	text := strings.NewReplacer("2026-11-02T", recentDay()+"T", "SETTINGS", settings, "BACKUP", backup, "CREATED", filepath.Dir(created)).Replace(nodeJournal)
	home.write(".spacevibe/journal.json", text)

	h := historyOf(t, r)
	if h[0].Count != 2 || h[1].Count != 1 || h[2].Count != 1 || h[0].Undone || !h[1].Undone || h[2].Undone {
		t.Errorf("history %+v", h)
	}
	_, err := Undo(r, "11111111-2222-3333-4444-555555555555")
	wantErr(t, err, 409)

	label := must(Undo(r, "e271c1e3-dfc2-4e9f-9d14-ba967210bee5"))
	if label != "Added allow rule Read (global)" {
		t.Errorf("label %q", label)
	}
	if got := home.read(".claude/settings.json"); got != "{\"model\":\"x\"}\n" {
		t.Errorf("settings %q", got)
	}
	if exists(filepath.Dir(created)) {
		t.Error("the created folder is still there")
	}

	// Recording a new entry rewrites the file; the foreign ops (with their numbers and nulls) survive.
	must(Record(r, "later", nil))
	after, err := locked(r, func(tx *Tx) ([]Entry, error) { return entriesForWriting(tx.r) })
	if err != nil {
		t.Fatal(err)
	}
	var gotLabels []string
	var undone []bool
	for _, e := range after {
		gotLabels = append(gotLabels, e.Label)
		undone = append(undone, e.Undone)
	}
	if !slices.Equal(gotLabels, []string{"later", "Added allow rule Read (global)", "Added Stop hook to Claude Code", "Removed Stop hook from Claude Code"}) ||
		!slices.Equal(undone, []bool{false, true, true, false}) {
		t.Errorf("entries %v %v", gotLabels, undone)
	}
	hook := after[2].Ops[0]
	if hook.Type() != "hook-added" {
		t.Errorf("type %q", hook.Type())
	}
	h2, _ := hook.JSON.Member("hook")
	timeout, _ := h2.Member("timeout")
	if n, _ := timeout.NumberText(); n != "5" {
		t.Errorf("timeout %v", timeout)
	}
	if m, _ := hook.JSON.Member("matcher"); m.Kind() != ojson.KindNull {
		t.Errorf("matcher %v", m)
	}
}

// Swift: JournalTests.swift "an entry written here has the shape the Node core reads"
func TestEntryHasNodeShape(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	file := home.write(".claude/settings.json", "{}\n")
	entry := must(EditJSON(r, file, "Added", nil, func(d *ojson.Document) (*ojson.Document, error) {
		return d.Set(ojson.Path("model"), ojson.String("x"))
	}))
	must(Undo(r, entry.ID))
	var raw []map[string]any
	if err := json.Unmarshal([]byte(home.read(".spacevibe/journal.json")), &raw); err != nil {
		t.Fatal(err)
	}
	op := raw[0]["ops"].([]any)[0].(map[string]any)
	keys := make([]string, 0, len(op))
	for k := range op {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	if !slices.Equal(keys, []string{"after", "backup", "existed", "file", "type"}) || op["type"] != "file-edited" || op["existed"] != true ||
		len(op["after"].(string)) != 64 || raw[0]["undone"] != true {
		t.Errorf("op %v undone %v", op, raw[0]["undone"])
	}
	if !strings.HasPrefix(op["backup"].(string), filepath.Join(home.data(), "trash")) {
		t.Errorf("backup %v", op["backup"])
	}
}

// Swift: JournalTests.swift "unknown id is 404 and a second undo is 409"
func TestUndoErrors(t *testing.T) {
	r := newHome(t).roots()
	_, err := Undo(r, "nope")
	wantErr(t, err, 404)
	entry := must(Record(r, "nothing", nil))
	must(Undo(r, entry.ID))
	_, err = Undo(r, entry.ID)
	if m := wantErr(t, err, 409); !strings.Contains(m, "already undone") {
		t.Errorf("message %q", m)
	}
}

// Swift: JournalTests.swift "created, moved and link-removed ops undo in reverse order"
func TestFileOpsUndoInReverse(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	skill := home.write(".claude/skills/a/SKILL.md", "---\nname: a\n---\n")
	skillDir := filepath.Dir(skill)
	shared := home.write("shared/b/SKILL.md", "---\nname: b\n---\n")
	link := home.symlink(filepath.Dir(shared), ".claude/skills/b")
	fresh := home.write(".claude/skills/c/SKILL.md", "c")

	removedDir := must(removePath(r, skillDir))
	removedLink := must(removePath(r, link))
	if removedDir.Type() != "moved" || removedLink.Type() != "link-removed" {
		t.Fatalf("types %q %q", removedDir.Type(), removedLink.Type())
	}
	if exists(skillDir) || !exists(shared) {
		t.Error("removing a link leaves its target; the folder is gone")
	}
	entry := must(Record(r, "Removed", []Op{removedDir, removedLink, Created(filepath.Dir(fresh))}))
	must(Undo(r, entry.ID))
	if !exists(skill) {
		t.Error("the skill did not come back")
	}
	if target, _ := os.Readlink(link); target != filepath.Dir(shared) {
		t.Errorf("link target %q", target)
	}
	if exists(fresh) {
		t.Error("a created folder goes to the trash")
	}
	if !historyOf(t, r)[0].Undone {
		t.Error("entry not marked undone")
	}
}

// Swift: JournalTests.swift "an entry that cannot be undone fully changes nothing"
func TestNeverPartial(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	created := home.write(".claude/made/file.txt", "keep me")
	edited := home.write(".claude/edited.json", "{\"a\":1}\n")
	backup := home.write(".spacevibe/trash/1-aaaaaaaa/edited.json", "{}\n")
	// Undo runs last op first: it moves `made` away, then refuses on the edited file (its hash does not match).
	entry := must(Record(r, "Two ops", []Op{
		FileEdited(edited, true, backup, strings.Repeat("0", 64)),
		Created(filepath.Dir(created)),
	}))
	_, err := Undo(r, entry.ID)
	wantErr(t, err, 409)
	if !exists(created) {
		t.Error("the first reversed op was not put back")
	}
	if home.read(".claude/edited.json") != "{\"a\":1}\n" {
		t.Error("the edited file changed")
	}
	if historyOf(t, r)[0].Undone {
		t.Error("entry marked undone")
	}
}

func (h tempHome) trashCopy(name, text string) string {
	return h.write(".spacevibe/trash/1-"+name+"/"+name, text)
}

// Swift: JournalTests.swift "moved: when a later-reversed op refuses, the op already reversed is moved back to the trash"
func TestMovedRollsBack(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	other := home.write(".claude/work/other.txt", "back again")
	otherTrash := home.trashCopy("other.txt", "saved")
	mine := home.write(".claude/work/mine.txt", "mine")
	removed := must(moveToTrash(r, mine))
	trashedMine, _ := removed.str("to")
	// Undo goes last op first: `mine` comes back, then `other` refuses because its path exists again.
	entry := must(Record(r, "Two moves", []Op{Moved(other, otherTrash), removed}))
	_, err := Undo(r, entry.ID)
	wantErr(t, err, 409)
	if exists(mine) {
		t.Error("the reversed op was not put back in the trash")
	}
	if data, _ := os.ReadFile(trashedMine); string(data) != "mine" {
		t.Errorf("trashed mine %q", data)
	}
	if data, _ := os.ReadFile(other); string(data) != "back again" || !exists(otherTrash) {
		t.Error("other or its saved copy changed")
	}
	if historyOf(t, r)[0].Undone {
		t.Error("entry marked undone")
	}
}

// Swift: JournalTests.swift "moved: refuses (409) when the original path exists again, and when the saved copy is gone"
func TestMovedRefusals(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	there := home.write(".claude/work/there.txt", "new file")
	trash := home.trashCopy("there.txt", "old file")
	exists1 := must(Record(r, "exists", []Op{Moved(there, trash)}))
	_, err := Undo(r, exists1.ID)
	if m := wantErr(t, err, 409); !strings.Contains(m, "already exists again") {
		t.Errorf("message %q", m)
	}
	if home.read(".claude/work/there.txt") != "new file" || home.read(".spacevibe/trash/1-there.txt/there.txt") != "old file" {
		t.Error("files changed")
	}
	gone := home.path(".claude/work/gone.txt")
	missing := must(Record(r, "gone", []Op{Moved(gone, home.path(".spacevibe/trash/9-zzzzzzzz/gone.txt"))}))
	_, err = Undo(r, missing.ID)
	if m := wantErr(t, err, 409); !strings.Contains(m, "saved copy") {
		t.Errorf("message %q", m)
	}
	if exists(gone) {
		t.Error("gone.txt appeared")
	}
	if h := historyOf(t, r); h[0].Undone || h[1].Undone {
		t.Errorf("history %+v", h)
	}
}

// Swift: JournalTests.swift "link-removed: refuses (409) when something exists at the path again"
func TestLinkRemovedRefusal(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	path := home.write(".claude/skills/b", "a file now")
	entry := must(Record(r, "link", []Op{LinkRemoved(path, "/somewhere/else")}))
	_, err := Undo(r, entry.ID)
	wantErr(t, err, 409)
	if home.read(".claude/skills/b") != "a file now" || historyOf(t, r)[0].Undone {
		t.Error("state changed")
	}
}

// Swift: JournalTests.swift "file-edited: refuses (409) when the saved copy is gone, and leaves the file as it is"
func TestFileEditedBackupGone(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	file := home.write(".claude/settings.json", "{\"a\":1}\n")
	op := FileEdited(file, true, home.path(".spacevibe/trash/1-aaaaaaaa/settings.json"), hashes.SHA256Hex([]byte("{\"a\":1}\n")))
	entry := must(Record(r, "edit", []Op{op}))
	_, err := Undo(r, entry.ID)
	if m := wantErr(t, err, 409); !strings.Contains(m, "saved copy") {
		t.Errorf("message %q", m)
	}
	if home.read(".claude/settings.json") != "{\"a\":1}\n" || historyOf(t, r)[0].Undone {
		t.Error("state changed")
	}
}

// Swift: JournalTests.swift "an op type this version does not know is refused (400) before anything is reversed"
func TestUnknownOpType(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	made := filepath.Dir(home.write(".claude/made/file.txt", "keep me"))
	mystery := Op{ojson.Object(member("type", ojson.String("teleported")), member("path", ojson.String(made)))}
	entry := must(Record(r, "Future op", []Op{mystery, Created(made)}))
	_, err := Undo(r, entry.ID)
	wantErr(t, err, 400)
	if !exists(filepath.Join(made, "file.txt")) || historyOf(t, r)[0].Undone {
		t.Error("something was reversed")
	}
	entries, _ := locked(r, func(tx *Tx) ([]Entry, error) { return entriesForWriting(tx.r) })
	if entries[0].Ops[0].Type() != "teleported" {
		t.Error("the foreign op was not kept as written")
	}
}

// Swift: JournalTests.swift "a journal.json that is not JSON makes record throw 409 and leaves the file untouched"
// G-fix.8 changed the last line: History reports the corrupt journal instead of an empty list.
func TestCorruptJournalRefusesRecord(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	file := home.write(".spacevibe/journal.json", "{ not json")
	_, err := Record(r, "later", nil)
	if m := wantErr(t, err, 409); m != UnreadableMessage {
		t.Errorf("message %q", m)
	}
	if home.read(".spacevibe/journal.json") != "{ not json" {
		t.Error("the corrupt file was replaced by a fresh history")
	}
	_, err = History(r)
	if m := wantErr(t, err, 409); m != UnreadableMessage {
		t.Errorf("History message %q", m)
	}
	_ = file
}

// Swift: JournalTests.swift "a journal.json holding a JSON object is refused the same way, by record and by undo (409, not 404)"
func TestObjectJournalRefusesRecordAndUndo(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	home.write(".spacevibe/journal.json", "{}")
	_, err := Record(r, "later", nil)
	wantErr(t, err, 409)
	_, err = Undo(r, "any")
	if m := wantErr(t, err, 409); m != UnreadableMessage {
		t.Errorf("message %q", m)
	}
	if home.read(".spacevibe/journal.json") != "{}" {
		t.Error("journal changed")
	}
	_ = coreerr.StatusConflict
}

// A journal element that is not an entry (no string id) is refused like a corrupt journal, never dropped on the next
// write. Swift's compactMap dropped it silently; that contradicted the fail-closed rule above (finding 2).
func TestJournalElementWithoutIDRefuses(t *testing.T) {
	for name, text := range map[string]string{
		"object without id": `[{"label":"no id","ops":[]}]`,
		"number":            `[1]`,
		"null":              `[null]`,
		"numeric id":        `[{"id":7,"label":"x"}]`,
		"after a good one":  `[{"id":"a","at":"t","label":"ok","ops":[]},"stray"]`,
	} {
		t.Run(name, func(t *testing.T) {
			home := newHome(t)
			r := home.roots()
			home.write(".spacevibe/journal.json", text)
			_, err := Record(r, "later", nil)
			if m := wantErr(t, err, 409); m != UnreadableMessage {
				t.Errorf("Record message %q", m)
			}
			_, err = Undo(r, "a")
			wantErr(t, err, 409)
			_, err = History(r)
			wantErr(t, err, 409)
			if home.read(".spacevibe/journal.json") != text {
				t.Error("the journal was rewritten")
			}
		})
	}
}
