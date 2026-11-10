package inventory

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"spacevibe.dev/core/internal/usage"
)

const addedReason = "Added in the last 24 hours"

// seenFixture is rowsHome with a finished scan and a clock the test moves.
type seenFixture struct {
	h       tempHome
	svc     *Service
	scanner *usage.Scanner
	now     time.Time
}

func newSeenFixture(t *testing.T) *seenFixture {
	t.Helper()
	f := &seenFixture{h: rowsHome(t), now: mustTime(t, "2026-12-01T00:00:00Z")}
	r := f.h.roots()
	f.scanner = usage.NewScanner(r)
	f.svc = NewService(r, f.scanner)
	f.svc.Now = func() time.Time { return f.now }
	if _, err := f.scanner.Scan(t.Context(), nil); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *seenFixture) rows(t *testing.T) LoadoutRows {
	t.Helper()
	rows, err := f.svc.Rows(t.Context())
	if err != nil {
		t.Fatalf("loadout.rows failed: %v", err)
	}
	return rows
}

// byModTime is what loadout.rows said before the store: the pure builder over a fresh read.
func (f *seenFixture) byModTime(t *testing.T) []byte {
	t.Helper()
	last, ok := f.scanner.Last()
	if !ok {
		t.Fatal("no scan result")
	}
	data, err := json.Marshal(BuildLoadoutRows(Read(f.h.roots()), usage.Ready(last), f.now))
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func marshal(t *testing.T, rows LoadoutRows) []byte {
	t.Helper()
	data, err := json.Marshal(rows)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func (f *seenFixture) storePath() string { return filepath.Join(f.h.data(), firstSeenFile) }

func (f *seenFixture) cell(t *testing.T, rows LoadoutRows, name string) Cell {
	t.Helper()
	for _, it := range rows.Items {
		if it.Name == name && it.CLI == Claude {
			return it.Cells.Claude
		}
	}
	t.Fatalf("no Claude item %q", name)
	return Cell{}
}

func (f *seenFixture) addSkill(name string, modified time.Time) {
	f.h.write(".claude/skills/"+name+"/SKILL.md", skillFile(name))
	f.h.setModified(f.h.path(".claude/skills/"+name+"/SKILL.md"), modified.Format(time.RFC3339))
}

func TestFirstSeenFreshDataFolderEqualsModificationTimes(t *testing.T) {
	f := newSeenFixture(t)
	got := marshal(t, f.rows(t))
	if want := f.byModTime(t); string(got) != string(want) {
		t.Errorf("first run differs from the modification-time output:\n got %s\nwant %s", got, want)
	}
	if _, err := os.Stat(f.storePath()); err != nil {
		t.Errorf("the store was not written: %v", err)
	}
}

func TestFirstSeenNewItemReadsAddedWhateverItsFileDate(t *testing.T) {
	f := newSeenFixture(t)
	f.rows(t) // the store now exists
	f.addSkill("fresh", f.now.Add(-90*24*time.Hour))

	if c := f.cell(t, f.rows(t), "fresh"); c.State != StatePending || c.Reason != addedReason {
		t.Errorf("fresh = %+v, want pending %q", c, addedReason)
	}
	// Without the store the 90-day-old file reads as an item that never ran, so the answers differ.
	if string(f.byModTime(t)) == string(marshal(t, f.rows(t))) {
		t.Error("the store changed nothing for a new item with an old file")
	}
	// A day later it is no longer "Added in the last 24 hours".
	f.now = f.now.Add(25 * time.Hour)
	if c := f.cell(t, f.rows(t), "fresh"); c.Reason == addedReason {
		t.Errorf("fresh still reads %q after 25 hours", addedReason)
	}
}

func TestFirstSeenKeptAcrossRemoveAndUndo(t *testing.T) {
	f := newSeenFixture(t)
	f.rows(t)
	skill := f.h.path(".claude/skills/solo")
	if err := os.Rename(skill, skill+".away"); err != nil {
		t.Fatal(err)
	}
	f.now = f.now.Add(10 * 24 * time.Hour)
	f.rows(t) // the item is absent from this read
	if err := os.Rename(skill+".away", skill); err != nil {
		t.Fatal(err)
	}
	if c := f.cell(t, f.rows(t), "solo"); c.Reason == addedReason {
		t.Errorf("solo after Remove and Undo reads %q: its first-seen time was lost", addedReason)
	}
}

func TestFirstSeenForgetsOnlyAfterNinetyDaysAbsent(t *testing.T) {
	f := newSeenFixture(t)
	nowMs := float64(f.now.UnixNano()) / 1e6
	day := float64((24 * time.Hour).Milliseconds())
	seeded := seenStore{Version: firstSeenVersion, Items: map[string]seenEntry{
		"gone-89-days": {First: 1, Last: nowMs - 89*day},
		"gone-91-days": {First: 1, Last: nowMs - 91*day},
	}}
	data, _ := json.Marshal(seeded)
	f.h.write(".spacevibe/"+firstSeenFile, data)
	f.rows(t)
	store, _, ok := loadSeen(f.storePath())
	if !ok {
		t.Fatal("store unreadable")
	}
	if _, kept := store.Items["gone-89-days"]; !kept {
		t.Error("an id absent for 89 days was dropped")
	}
	if _, kept := store.Items["gone-91-days"]; kept {
		t.Error("an id absent for 91 days was kept")
	}
}

func TestFirstSeenReadThatChangesNothingDoesNotWrite(t *testing.T) {
	f := newSeenFixture(t)
	f.rows(t)
	before, err := os.ReadFile(f.storePath())
	if err != nil {
		t.Fatal(err)
	}
	f.now = f.now.Add(time.Hour)
	f.rows(t)
	after, _ := os.ReadFile(f.storePath())
	if string(before) != string(after) {
		t.Errorf("the store was rewritten by a read that changed nothing:\n%s\n%s", before, after)
	}
}

func TestFirstSeenUnwritableDataFolderStillAnswers(t *testing.T) {
	f := newSeenFixture(t)
	// A file where the data folder should be: the folder cannot be created, whoever runs the test.
	if err := os.RemoveAll(f.h.data()); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(f.h.data(), []byte("not a folder"), 0o600); err != nil {
		t.Fatal(err)
	}
	got := marshal(t, f.rows(t))
	if want := f.byModTime(t); string(got) != string(want) {
		t.Errorf("an unwritable data folder changed the answer:\n got %s\nwant %s", got, want)
	}
	if content, _ := os.ReadFile(f.h.data()); string(content) != "not a folder" {
		t.Errorf("the data path was touched: %q", content)
	}
}

func TestFirstSeenCorruptStoreStillAnswersAndIsLeftAlone(t *testing.T) {
	for name, content := range map[string]string{
		"garbage":       "{not json",
		"newer version": `{"version":99,"items":{}}`,
		"no items":      `{"version":1}`,
	} {
		t.Run(name, func(t *testing.T) {
			f := newSeenFixture(t)
			f.h.write(".spacevibe/"+firstSeenFile, content)
			got := marshal(t, f.rows(t))
			if want := f.byModTime(t); string(got) != string(want) {
				t.Errorf("a %s store changed the answer", name)
			}
			if kept, _ := os.ReadFile(f.storePath()); string(kept) != content {
				t.Errorf("the %s store was overwritten: %q", name, kept)
			}
		})
	}
}
