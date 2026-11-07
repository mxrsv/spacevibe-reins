package mutate

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"

	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/ojson"
)

// WriteConcurrencyTests.swift: the app runs every write and every Undo on its own thread. These drive the engine the
// same way: many goroutines at once, against one journal and one settings file. Go tests run with -timeout so a
// re-entry into the (non re-entrant) lock shows up as a fast hang.

func goroutines(n int, fn func(i int) error) []error {
	var wg sync.WaitGroup
	errs := make([]error, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs[i] = fn(i)
		}()
	}
	wg.Wait()
	return errs
}

func noErrors(t *testing.T, errs []error) {
	t.Helper()
	for i, err := range errs {
		if err != nil {
			t.Errorf("%d: %v", i, err)
			return
		}
	}
}

// Swift: WriteConcurrencyTests.swift "200 concurrent records all survive, in the journal, with no temp file left"
func TestConcurrentRecordsAllSurvive(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	noErrors(t, goroutines(200, func(i int) error { _, err := Record(r, fmt.Sprintf("entry %d", i), nil); return err }))
	got := labelsOf(historyOf(t, r))
	slices.Sort(got)
	var want []string
	for i := 0; i < 200; i++ {
		want = append(want, fmt.Sprintf("entry %d", i))
	}
	slices.Sort(want)
	if !slices.Equal(got, want) || len(strayTemp(r.Data)) != 0 {
		t.Errorf("%d labels, stray %v", len(got), strayTemp(r.Data))
	}
}

// Swift: WriteConcurrencyTests.swift "50 concurrent rule additions to one settings.json all land, each with its own journal entry"
// (the rule additions are EditJSON appends to permissions.allow, the call a rule write makes; the rules package ports the rest).
func TestConcurrentSettingsAppends(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".claude/settings.json", "{\n  \"model\": \"keep\"\n}\n")
	noErrors(t, goroutines(50, func(i int) error {
		_, err := EditJSON(sb.r, sb.settings, fmt.Sprintf("Added allow rule %d", i), nil, addRule(fmt.Sprintf("Bash(rule-%d:*)", i)))
		return err
	}))
	doc := must(ojson.ParseString(sb.bytes()))
	list, _ := doc.Get(ojson.Key("permissions"), ojson.Key("allow"))
	items, _ := list.ArrayValue()
	var allowed []string
	for _, it := range items {
		s, _ := it.StringValue()
		allowed = append(allowed, s)
	}
	slices.Sort(allowed)
	var want []string
	for i := 0; i < 50; i++ {
		want = append(want, fmt.Sprintf("Bash(rule-%d:*)", i))
	}
	slices.Sort(want)
	model, _ := doc.Get(ojson.Key("model"))
	if !slices.Equal(allowed, want) || !valueIs(model, "keep") || len(historyOf(t, sb.r)) != 50 || len(sb.stray()) != 0 {
		t.Errorf("%d rules landed, %d entries", len(allowed), len(historyOf(t, sb.r)))
	}
}

// Swift: WriteConcurrencyTests.swift "an Undo interleaved with writes never loses an entry"
func TestUndoInterleavedNeverLosesAnEntry(t *testing.T) {
	home := newHome(t)
	r := home.roots()
	var older []Entry
	for i := 0; i < 20; i++ {
		folder := filepath.Dir(home.write(fmt.Sprintf(".claude/made/%d/file.txt", i), "x"))
		older = append(older, must(Record(r, fmt.Sprintf("older %d", i), []Op{Created(folder)})))
	}
	noErrors(t, goroutines(120, func(i int) error {
		if i%6 == 0 {
			_, err := Undo(r, older[i/6].ID)
			return err
		}
		_, err := Record(r, fmt.Sprintf("new %d", i), nil)
		return err
	}))
	h := historyOf(t, r)
	undone, open := 0, 0
	for _, e := range h {
		if e.Undone {
			undone++
			if !strings.HasPrefix(e.Label, "older ") {
				t.Errorf("undone %q", e.Label)
			}
		} else {
			open++
		}
	}
	if len(h) != 120 || undone != 20 || open != 100 {
		t.Errorf("%d entries, %d undone, %d open", len(h), undone, open)
	}
	for i := 0; i < 20; i++ {
		if exists(home.path(fmt.Sprintf(".claude/made/%d", i))) {
			t.Errorf("folder %d is not in the trash", i)
		}
	}
	if len(strayTemp(r.Data)) != 0 {
		t.Error("stray temp files")
	}
}

// Swift: WriteConcurrencyTests.swift "writers next to one target never share a temp file (the lock is not what protects this)"
func TestUniqueTempNames(t *testing.T) {
	home := newHome(t)
	target := home.path("shared/file.txt")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	noErrors(t, goroutines(50, func(i int) error {
		return fsx.AtomicWrite(target, []byte(fmt.Sprintf("writer %d\n", i)), 0o600, fsx.AtomicWriteOptions{})
	}))
	text := must(os.ReadFile(target))
	if !strings.HasPrefix(string(text), "writer ") || !strings.HasSuffix(string(text), "\n") || len(strayTemp(filepath.Dir(target))) != 0 {
		t.Errorf("target %q", text)
	}
}

// Swift: WriteConcurrencyTests.swift "a file changed by someone else between the read and the rename is left alone (409)"
func TestExternalChangeBeforeRename(t *testing.T) {
	sb := newSandbox(t)
	file := sb.write(".claude/settings.json", "{\n  \"model\": \"mine\"\n}\n")
	next := "{\n  \"model\": \"next\"\n}\n"
	_, err := Apply(sb.r, file,
		func(string) error { // runs on the temp file, after the read and before the rename: another process writes the target
			return os.WriteFile(file, []byte("{\"model\":\"theirs\"}\n"), 0o644)
		},
		func(*string) (*string, error) { return &next, nil })
	wantErr(t, err, 409)
	if sb.bytes() != "{\"model\":\"theirs\"}\n" || len(sb.stray()) != 0 || !sb.journalEmpty() {
		t.Error("the other writer's file was overwritten, or a temp file or entry is left")
	}
	if len(sb.trashSlots()) != 0 {
		t.Errorf("the unused backup slot is not removed: %v", sb.trashSlots())
	}
}

// Swift: WriteConcurrencyTests.swift "a file created by someone else while a new file is being written is left alone (409)"
func TestExternalCreateBeforeRename(t *testing.T) {
	sb := newSandbox(t)
	next := "{\"model\":\"x\"}\n"
	_, err := Apply(sb.r, sb.settings,
		func(string) error {
			if err := os.MkdirAll(filepath.Dir(sb.settings), 0o755); err != nil {
				return err
			}
			return os.WriteFile(sb.settings, []byte("{}\n"), 0o644)
		},
		func(*string) (*string, error) { return &next, nil })
	wantErr(t, err, 409)
	if sb.bytes() != "{}\n" || len(sb.stray()) != 0 {
		t.Error("the other writer's file was overwritten, or a temp file is left")
	}
}

// G-fix.4: the journal's read-modify-write runs under the cross-process lock. Two processes record into one journal
// at once (the Swift app and a core are two such processes); no entry may be lost. The test binary re-executes itself as
// the writer (TestMain, MUTATE_TEST_JOURNAL_WRITER).
func TestTwoProcessesNeverLoseAJournalEntry(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("the Windows lock is a documented no-op (fsx flock_other.go)")
	}
	const count = 60 // 2 x 60 stays under the 200 entry limit
	home := newHome(t)
	var cmds []*exec.Cmd
	for _, id := range []string{"A", "B"} {
		cmd := exec.Command(os.Args[0], "-test.run=^$")
		cmd.Env = append(os.Environ(), envJournalWriter+"="+home.root+"|"+id+"|"+strconv.Itoa(count))
		cmd.Stderr = os.Stderr
		if err := cmd.Start(); err != nil {
			t.Fatal(err)
		}
		cmds = append(cmds, cmd)
	}
	for _, cmd := range cmds {
		if err := cmd.Wait(); err != nil {
			t.Fatalf("writer process failed: %v", err)
		}
	}
	seen := map[string]int{}
	for _, e := range historyOf(t, home.roots()) {
		seen[e.Label]++
	}
	for _, id := range []string{"A", "B"} {
		for i := 0; i < count; i++ {
			if seen[fmt.Sprintf("%s-%d", id, i)] != 1 {
				t.Fatalf("entry %s-%d appears %d times; %d entries of %d", id, i, seen[fmt.Sprintf("%s-%d", id, i)], len(seen), 2*count)
			}
		}
	}
	if len(strayTemp(home.data())) != 0 {
		t.Errorf("stray %v", strayTemp(home.data()))
	}
}
