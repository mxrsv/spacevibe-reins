package fsx

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"spacevibe.dev/core/internal/coreerr"
)

// appendLine is the read-modify-write every writer test races on: read the file, add a line, write
// it back atomically. Without the write lock two writers read the same bytes and one line is lost.
// It is an "unlocked body": it never takes the lock itself.
func appendLine(file, line string) error {
	old, err := os.ReadFile(file)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	return AtomicWrite(file, append(old, []byte(line+"\n")...), 0o600, AtomicWriteOptions{})
}

// appendLineLocked is the "locked entry" for appendLine.
func appendLineLocked(dataDir, file, line string) error {
	return WithWriteLock(dataDir, func() error { return appendLine(file, line) })
}

func lines(t *testing.T, file string) []string {
	t.Helper()
	text := readFile(t, file)
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

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
	data := tempDir(t)
	journal := filepath.Join(data, "journal.txt")
	noErrors(t, goroutines(200, func(i int) error { return appendLineLocked(data, journal, fmt.Sprintf("entry %d", i)) }))
	got := lines(t, journal)
	sort.Strings(got)
	want := make([]string, 200)
	for i := range want {
		want[i] = fmt.Sprintf("entry %d", i)
	}
	sort.Strings(want)
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("%d lines, want 200 distinct", len(got))
	}
	if len(strayTempFiles(t, data)) != 0 {
		t.Errorf("stray %v", strayTempFiles(t, data))
	}
}

// Swift: WriteConcurrencyTests.swift "50 concurrent rule additions to one settings.json all land, each with its own journal entry"
// The edit re-checks the bytes just before the rename, as FileEdit does: under the lock none may be refused.
func TestConcurrentSettingsAppendsNeverConflict(t *testing.T) {
	data := tempDir(t)
	settings := filepath.Join(tempDir(t), ".claude", "settings.json")
	writeFile(t, settings, "model=keep\n", 0o600)
	journal := filepath.Join(data, "journal.txt")
	errs := goroutines(50, func(i int) error {
		return WithWriteLock(data, func() error {
			before, err := os.ReadFile(settings)
			if err != nil {
				return err
			}
			err = AtomicWrite(settings, append(append([]byte{}, before...), fmt.Sprintf("rule-%d\n", i)...), 0o600, AtomicWriteOptions{
				BeforeRename: func() error {
					if !UnchangedSince(settings, before) {
						return coreerr.NewStatus("changed", coreerr.StatusConflict)
					}
					return nil
				},
			})
			if err != nil {
				return err
			}
			return appendLine(journal, fmt.Sprintf("added rule-%d", i))
		})
	})
	noErrors(t, errs)
	got := lines(t, settings)
	if len(got) != 51 || got[0] != "model=keep" {
		t.Errorf("settings has %d lines, first %q", len(got), got[0])
	}
	if n := len(lines(t, journal)); n != 50 {
		t.Errorf("journal has %d entries", n)
	}
	seen := map[string]bool{}
	for _, l := range got[1:] {
		seen[l] = true
	}
	if len(seen) != 50 {
		t.Errorf("%d distinct rules", len(seen))
	}
	if len(strayTempFiles(t, filepath.Dir(settings), data)) != 0 {
		t.Error("stray temp file")
	}
}

// Swift: WriteConcurrencyTests.swift "an Undo interleaved with writes never loses an entry"
// An "undo" rewrites an older line (marks it) while new entries are added; every entry survives.
func TestUndoInterleavedNeverLosesAnEntry(t *testing.T) {
	data := tempDir(t)
	journal := filepath.Join(data, "journal.txt")
	for i := 0; i < 20; i++ {
		if err := appendLineLocked(data, journal, fmt.Sprintf("older %d", i)); err != nil {
			t.Fatal(err)
		}
	}
	noErrors(t, goroutines(120, func(i int) error {
		if i%6 != 0 {
			return appendLineLocked(data, journal, fmt.Sprintf("new %d", i))
		}
		target := fmt.Sprintf("older %d", i/6)
		return WithWriteLock(data, func() error {
			b, err := os.ReadFile(journal)
			if err != nil {
				return err
			}
			next := strings.Replace(string(b), target+"\n", target+" undone\n", 1)
			return AtomicWrite(journal, []byte(next), 0o600, AtomicWriteOptions{})
		})
	}))
	all := lines(t, journal)
	undone, fresh := 0, 0
	for _, l := range all {
		switch {
		case strings.HasSuffix(l, " undone"):
			undone++
		case strings.HasPrefix(l, "new "):
			fresh++
		}
	}
	if len(all) != 120 || undone != 20 || fresh != 100 {
		t.Errorf("lines %d undone %d new %d", len(all), undone, fresh)
	}
}

func TestWriteLockIsMutuallyExclusive(t *testing.T) {
	data := tempDir(t)
	var inside, overlaps atomic.Int32
	noErrors(t, goroutines(100, func(int) error {
		return WithWriteLock(data, func() error {
			if inside.Add(1) != 1 {
				overlaps.Add(1)
			}
			runtime.Gosched()
			inside.Add(-1)
			return nil
		})
	}))
	if overlaps.Load() != 0 {
		t.Errorf("%d overlaps", overlaps.Load())
	}
}

func TestWriteLockReturnsBodyErrorAndValue(t *testing.T) {
	data := tempDir(t)
	boom := coreerr.NewStatus("boom", coreerr.StatusConflict)
	if err := WithWriteLock(data, func() error { return boom }); err != boom {
		t.Errorf("err %v", err)
	}
	v, err := WithWriteLockValue(data, func() (int, error) { return 7, nil })
	if v != 7 || err != nil {
		t.Errorf("%d, %v", v, err)
	}
	// The lock was released: another entry works.
	if err := WithWriteLock(data, func() error { return nil }); err != nil {
		t.Error(err)
	}
	if _, err := os.Stat(filepath.Join(data, LockFileName)); err != nil {
		t.Error("write.lock was not created")
	}
}

func TestWriteLockFailsClosed(t *testing.T) {
	skipOnWindows(t)
	parent := tempDir(t)
	blocker := filepath.Join(parent, "data")
	writeFile(t, blocker, "a file where the data folder should be", 0o600)
	ran := false
	err := WithWriteLock(blocker, func() error { ran = true; return nil })
	wantStatus(t, err, coreerr.StatusInternalFailure)
	if ran {
		t.Error("the body ran without the lock")
	}
}

// editLocked-style functions for the nesting pattern test.
type store struct {
	data, file string
	calls      []string
}

// Add is a locked entry: it takes the lock once and calls the unlocked bodies.
func (s *store) Add(line string) error {
	return WithWriteLock(s.data, func() error { return s.addLocked(line) })
}

// AddTwice nests the way addHook -> FileEdit -> Journal does: one lock, bodies calling bodies.
func (s *store) AddTwice(line string) error {
	return WithWriteLock(s.data, func() error {
		if err := s.addLocked(line + "-1"); err != nil {
			return err
		}
		return s.addLocked(line + "-2")
	})
}

func (s *store) addLocked(line string) error {
	s.calls = append(s.calls, line)
	return appendLine(s.file, line)
}

// The locked entry / unlocked body convention: nested use works because only the entry locks, and
// calling an entry from inside a body would block (checked with a timeout in a goroutine).
func TestLockedEntryUnlockedBodyPattern(t *testing.T) {
	data := tempDir(t)
	s := &store{data: data, file: filepath.Join(data, "f.txt")}
	if err := s.AddTwice("a"); err != nil {
		t.Fatal(err)
	}
	if err := s.Add("b"); err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(lines(t, s.file), ","); got != "a-1,a-2,b" {
		t.Errorf("got %s", got)
	}
}

func TestNestedEntryDoesNotReenter(t *testing.T) {
	data := tempDir(t)
	done := make(chan struct{})
	inner := make(chan struct{})
	go func() {
		// Deliberately wrong use: an entry called from inside a body. It must block, not proceed.
		_ = WithWriteLock(data, func() error {
			go func() { _ = WithWriteLock(data, func() error { return nil }); close(inner) }()
			select {
			case <-inner:
				t.Error("a nested entry ran while the lock was held")
			case <-timeoutAfterMillis(150):
			}
			return nil
		})
		close(done)
	}()
	<-done
	<-inner // the blocked entry runs once the outer one lets go; wait so it cannot touch the folder after cleanup
}

// ---- two processes ---------------------------------------------------------------------------

const (
	envWriter  = "FSX_TEST_WRITER"  // "<dataDir>:<id>:<count>"
	envNoLock  = "FSX_TEST_NO_LOCK" // set by the control run only
	sharedFile = "shared.txt"
)

// TestMain turns the test binary into a writer when envWriter is set (the two-process test re-execs it).
func TestMain(m *testing.M) {
	if spec := os.Getenv(envWriter); spec != "" {
		os.Exit(runWriter(spec))
	}
	os.Exit(m.Run())
}

func runWriter(spec string) int {
	parts := strings.Split(spec, "|")
	if len(parts) != 3 {
		return 2
	}
	data, id := parts[0], parts[1]
	count, err := strconv.Atoi(parts[2])
	if err != nil {
		return 2
	}
	file := filepath.Join(data, sharedFile)
	for i := 0; i < count; i++ {
		line := fmt.Sprintf("%s-%d", id, i)
		if os.Getenv(envNoLock) != "" {
			err = appendLine(file, line)
		} else {
			err = appendLineLocked(data, file, line)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, "writer", id, "failed:", err)
			return 1
		}
	}
	return 0
}

func runTwoWriters(t *testing.T, data string, count int, extraEnv ...string) {
	t.Helper()
	var cmds []*exec.Cmd
	for _, id := range []string{"A", "B"} {
		cmd := exec.Command(os.Args[0], "-test.run=^$")
		cmd.Env = append(os.Environ(), envWriter+"="+data+"|"+id+"|"+strconv.Itoa(count))
		cmd.Env = append(cmd.Env, extraEnv...)
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
}

// New (G1.7): two processes append to one file under the lock on one data folder; no entry is lost.
func TestTwoProcessesNeverLoseAnEntry(t *testing.T) {
	skipOnWindows(t) // the Windows lock is a documented no-op (flock_other.go)
	const count = 60
	data := tempDir(t)
	runTwoWriters(t, data, count)
	got := lines(t, filepath.Join(data, sharedFile))
	seen := map[string]int{}
	for _, l := range got {
		seen[l]++
	}
	for _, id := range []string{"A", "B"} {
		for i := 0; i < count; i++ {
			if seen[fmt.Sprintf("%s-%d", id, i)] != 1 {
				t.Fatalf("entry %s-%d appears %d times; %d lines of %d", id, i, seen[fmt.Sprintf("%s-%d", id, i)], len(got), 2*count)
			}
		}
	}
	if len(got) != 2*count {
		t.Errorf("%d lines, want %d", len(got), 2*count)
	}
	if len(strayTempFiles(t, data)) != 0 {
		t.Errorf("stray %v", strayTempFiles(t, data))
	}
}

// Control: the same two writers WITHOUT the lock lose entries, so the test above can fail. It is
// skipped unless FSX_TEST_CONTROL=1 because losing entries is a race, not a guarantee.
func TestTwoProcessesWithoutTheLockLoseEntries(t *testing.T) {
	skipOnWindows(t)
	if os.Getenv("FSX_TEST_CONTROL") != "1" {
		t.Skip("manual control run: FSX_TEST_CONTROL=1")
	}
	data := tempDir(t)
	runTwoWriters(t, data, 60, envNoLock+"=1")
	if n := len(lines(t, filepath.Join(data, sharedFile))); n >= 120 {
		t.Errorf("no entry lost (%d); the control did not race", n)
	}
}

func timeoutAfterMillis(n int) <-chan time.Time {
	return time.After(time.Duration(n) * time.Millisecond)
}
