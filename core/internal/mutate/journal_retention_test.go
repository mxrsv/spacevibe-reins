package mutate

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// slotName is the name of a trash folder made at the given time.
func slotName(at time.Time, hex string) string { return fmt.Sprintf("%d-%s", at.UnixMilli(), hex) }

// writeJournalFile writes entries (newest first) as journal.json; each op is a raw map so a test can name any kind.
func writeJournalFile(h tempHome, entries ...map[string]any) {
	h.t.Helper()
	data, err := json.Marshal(entries)
	if err != nil {
		h.t.Fatal(err)
	}
	h.write(".spacevibe/journal.json", string(data))
}

func journalEntry(id string, at time.Time, ops ...map[string]any) map[string]any {
	return map[string]any{"id": id, "at": at.UTC().Format("2006-01-02T15:04:05.000Z"), "label": id, "ops": ops}
}

func TestJournalCutDeletesItsTrashCopies(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	file := home.write(".claude/work/f.txt", "x")
	for i := 0; i < JournalLimit+1; i++ {
		op := must(moveToTrash(r, file))
		to, _ := op.str("to")
		home.write(".claude/work/f.txt", "x")
		must(Record(r, fmt.Sprintf("edit %d", i), []Op{Moved(file, to)}))
	}
	if got := len(names(trashDir(r))); got != JournalLimit {
		t.Errorf("%d slots after %d edits, want %d", got, JournalLimit+1, JournalLimit)
	}
	entries := must(locked(r, func(tx *Tx) ([]Entry, error) { return entriesForWriting(tx.r) }))
	if len(entries) != JournalLimit {
		t.Fatalf("%d entries", len(entries))
	}
	for _, e := range entries {
		to, _ := e.Ops[0].str("to")
		if !exists(to) {
			t.Fatalf("entry %q lost its copy", e.Label)
		}
	}
}

func TestJournalEntryOlderThanThirtyDaysGoesWithItsSlot(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	now := time.Now()
	old := home.write(".spacevibe/trash/"+slotName(now, "aaaaaaaa")+"/settings.json", "old")
	young := home.write(".spacevibe/trash/"+slotName(now, "bbbbbbbb")+"/settings.json", "young")
	writeJournalFile(home,
		journalEntry("young", now.Add(-29*24*time.Hour), map[string]any{"type": "moved", "from": home.path(".claude/a"), "to": young}),
		journalEntry("old", now.Add(-31*24*time.Hour), map[string]any{"type": "moved", "from": home.path(".claude/b"), "to": old}))
	must(Record(r, "new", nil))
	if exists(old) || exists(filepath.Dir(old)) {
		t.Error("the slot of the 31-day-old entry is still there")
	}
	if !exists(young) {
		t.Error("the slot of the 29-day-old entry was removed")
	}
	if h := historyOf(t, r); len(h) != 2 || h[1].Label != "young" {
		t.Errorf("history %+v", h)
	}
}

func TestSweepKeepsReferencedAndYoungSlots(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	now := time.Now()
	ancient := now.Add(-90 * 24 * time.Hour)
	live := home.write(".spacevibe/trash/"+slotName(ancient, "11111111")+"/live.txt", "live")
	nested := home.write(".spacevibe/trash/"+slotName(ancient, "22222222")+"/nested.txt", "nested")
	orphan := home.write(".spacevibe/trash/"+slotName(ancient, "33333333")+"/orphan.txt", "orphan")
	young := home.write(".spacevibe/trash/"+slotName(now.Add(-29*24*time.Hour), "44444444")+"/young.txt", "young")
	foreign := home.write(".spacevibe/trash/1-not-a-slot/keep.txt", "foreign")
	writeJournalFile(home, journalEntry("live", now,
		map[string]any{"type": "file-edited", "file": home.path(".claude/s.json"), "existed": true, "backup": live, "after": "h"},
		// An op kind this version cannot undo, with the path under a key and a depth nobody knows: still a reference.
		map[string]any{"type": "from-a-newer-version", "detail": map[string]any{"copies": []any{map[string]any{"at": nested}}}}))
	must(Record(r, "new", nil))
	for name, p := range map[string]string{"live": live, "nested": nested, "young": young, "foreign": foreign} {
		if !exists(p) {
			t.Errorf("%s slot was removed", name)
		}
	}
	if exists(orphan) || exists(filepath.Dir(orphan)) {
		t.Error("the old unreferenced slot is still there")
	}
}

func TestPruneNeverRemovesOutsideTheTrash(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	now := time.Now()
	precious := home.write(".claude/precious/keep.txt", "keep")
	dataFile := home.write(".spacevibe/not-trash.txt", "keep")
	outsideTarget := home.write("elsewhere/target/keep.txt", "keep")
	if err := os.MkdirAll(trashDir(r), 0o700); err != nil {
		t.Fatal(err)
	}
	linkSlot := filepath.Join(trashDir(r), slotName(now.Add(-90*24*time.Hour), "55555555"))
	if err := os.Symlink(filepath.Dir(outsideTarget), linkSlot); err != nil {
		t.Fatal(err)
	}
	cutAt := now.Add(-31 * 24 * time.Hour)
	writeJournalFile(home, journalEntry("crafted", cutAt,
		map[string]any{"type": "moved", "from": home.path(".claude/x"), "to": precious},
		map[string]any{"type": "file-edited", "file": home.path(".claude/y"), "backup": dataFile},
		map[string]any{"type": "moved", "from": home.path(".claude/z"), "to": filepath.Join(trashDir(r), "slot", "..", "..", "not-trash.txt")},
		map[string]any{"type": "moved", "from": home.path(".claude/w"), "to": trashDir(r)},
		map[string]any{"type": "moved", "from": home.path(".claude/v"), "to": filepath.Join(linkSlot, "keep.txt")}))
	must(Record(r, "new", nil))
	for _, p := range []string{precious, dataFile, outsideTarget, trashDir(r)} {
		if !exists(p) {
			t.Errorf("%s was removed", p)
		}
	}
}

// A dropped entry names only slots this package made: a file or a folder with another name directly in the trash stays.
func TestPruneSkipsCutNamesThatAreNotSlotFolders(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	now := time.Now()
	file := home.write(".spacevibe/trash/notes.txt", "keep")
	odd := home.write(".spacevibe/trash/odd-name/keep.txt", "keep")
	slotFile := home.write(".spacevibe/trash/"+slotName(now, "66666666"), "a file with a slot name")
	writeJournalFile(home, journalEntry("crafted", now.Add(-31*24*time.Hour),
		map[string]any{"type": "moved", "from": home.path(".claude/a"), "to": file},
		map[string]any{"type": "moved", "from": home.path(".claude/b"), "to": odd},
		map[string]any{"type": "moved", "from": home.path(".claude/c"), "to": slotFile}))
	must(Record(r, "new", nil))
	for name, p := range map[string]string{"file": file, "odd folder": odd, "file with a slot name": slotFile} {
		if !exists(p) {
			t.Errorf("%s was removed", name)
		}
	}
}
