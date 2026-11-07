package fsx

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
)

// canary stands in for a secret value: it must never show up in an error.
const canary = "CANARY-sk-live-0123456789"

// tempDir is a real path (symlinks resolved), so path comparisons are stable.
func tempDir(t *testing.T) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return dir
}

func writeFile(t *testing.T, path, content string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), mode); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func modeOf(t *testing.T, path string) os.FileMode {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	return info.Mode().Perm()
}

// strayTempFiles lists every .tmp in the folders, not only SpaceVibe's own: the stricter check.
func strayTempFiles(t *testing.T, folders ...string) []string {
	t.Helper()
	var out []string
	for _, folder := range folders {
		entries, _ := os.ReadDir(folder)
		for _, e := range entries {
			if strings.HasSuffix(e.Name(), ".tmp") {
				out = append(out, filepath.Join(folder, e.Name()))
			}
		}
	}
	return out
}

func skipOnWindows(t *testing.T) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("POSIX permission bits and links")
	}
}

func wantStatus(t *testing.T, err error, status int) coreerr.Error {
	t.Helper()
	e, ok := coreerr.As(err)
	if !ok || e.Status != status {
		t.Fatalf("want a coreerr with status %d, got %v", status, err)
	}
	return e
}

var tempPattern = regexp.MustCompile(`^file\.txt\.spacevibe-\d+-[0-9a-f]{8}\.tmp$`)

func TestAtomicWriteTempNameAndContent(t *testing.T) {
	dir := tempDir(t)
	target := filepath.Join(dir, "file.txt")
	writeFile(t, target, "old", 0o600)
	var seen []string
	err := AtomicWrite(target, []byte("new"), 0o600, AtomicWriteOptions{Validate: func(written []byte) error {
		entries, _ := os.ReadDir(dir)
		for _, e := range entries {
			seen = append(seen, e.Name())
		}
		if string(written) != "new" {
			t.Errorf("validate got %q", written)
		}
		return nil
	}})
	if err != nil {
		t.Fatal(err)
	}
	temps := 0
	for _, name := range seen {
		if tempPattern.MatchString(name) {
			temps++
			if !strings.Contains(name, fmt.Sprintf("-%d-", os.Getpid())) {
				t.Errorf("temp name %q lacks the pid", name)
			}
		}
	}
	if temps != 1 {
		t.Errorf("want one temp file named <path>.spacevibe-<pid>-<8 hex>.tmp during the write, saw %v", seen)
	}
	if readFile(t, target) != "new" || len(strayTempFiles(t, dir)) != 0 {
		t.Errorf("target %q, stray %v", readFile(t, target), strayTempFiles(t, dir))
	}
}

// Swift: FileEditTests.swift "set then undo restores identical bytes and keeps the mode, for tab, space and CRLF files" (mode part)
func TestAtomicWriteSetsExactModeDespiteUmask(t *testing.T) {
	skipOnWindows(t)
	for _, mode := range []os.FileMode{0o640, 0o664, 0o600, 0o666, 0o700} {
		dir := tempDir(t)
		target := filepath.Join(dir, "file.txt")
		if err := AtomicWrite(target, []byte("x"), mode, AtomicWriteOptions{}); err != nil {
			t.Fatal(err)
		}
		if got := modeOf(t, target); got != mode {
			t.Errorf("mode %o, want %o", got, mode)
		}
	}
	// An existing file's mode is kept when the caller passes the mode ResolveTarget returned.
	dir := tempDir(t)
	target := filepath.Join(dir, "settings.json")
	writeFile(t, target, "{}\n", 0o640)
	resolved, err := ResolveTarget(target)
	if err != nil {
		t.Fatal(err)
	}
	if err := AtomicWrite(resolved.Real, []byte("{\"a\":1}\n"), resolved.Mode, AtomicWriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if modeOf(t, target) != 0o640 {
		t.Errorf("mode %o after rewrite, want 640", modeOf(t, target))
	}
}

// Swift: FileEditTests.swift "a validator that rejects the temp file leaves the target, the folder and the journal untouched"
func TestAtomicWriteValidatorRejects(t *testing.T) {
	dir := tempDir(t)
	target := filepath.Join(dir, "settings.json")
	writeFile(t, target, "{\"model\":\"x\"}\n", 0o600)
	reject := coreerr.NewStatus("rejected", coreerr.StatusConflict)
	err := AtomicWrite(target, []byte("{\"model\":\"y\"}\n"), 0o600, AtomicWriteOptions{Validate: func([]byte) error { return reject }})
	if err != reject {
		t.Fatalf("want the validator's error as is, got %v", err)
	}
	if readFile(t, target) != "{\"model\":\"x\"}\n" {
		t.Errorf("target changed: %q", readFile(t, target))
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 1 {
		t.Errorf("folder not untouched: %v", entries)
	}
}

func TestAtomicWriteBeforeRenameAbort(t *testing.T) {
	dir := tempDir(t)
	target := filepath.Join(dir, "file.txt")
	writeFile(t, target, "old", 0o600)
	stop := coreerr.NewStatus("stop", coreerr.StatusConflict)
	order := ""
	err := AtomicWrite(target, []byte("new"), 0o600, AtomicWriteOptions{
		Validate:     func([]byte) error { order += "v"; return nil },
		BeforeRename: func() error { order += "b"; return stop },
	})
	if err != stop || order != "vb" {
		t.Fatalf("err %v, order %q", err, order)
	}
	if readFile(t, target) != "old" || len(strayTempFiles(t, dir)) != 0 {
		t.Errorf("target %q stray %v", readFile(t, target), strayTempFiles(t, dir))
	}
}

func TestAtomicWriteFailuresAre500AndNeverQuoteContent(t *testing.T) {
	dir := tempDir(t)
	// The folder is missing: the temp file cannot be created.
	err := AtomicWrite(filepath.Join(dir, "missing", "file.txt"), []byte(canary), 0o600, AtomicWriteOptions{})
	e := wantStatus(t, err, coreerr.StatusInternalFailure)
	if strings.Contains(e.Message, canary) || !strings.Contains(e.Message, "Nothing was changed") {
		t.Errorf("message %q", e.Message)
	}
	// The target is a non-empty directory: the rename fails and the temp file is removed.
	target := filepath.Join(dir, "target")
	writeFile(t, filepath.Join(target, "inner"), "x", 0o600)
	err = AtomicWrite(target, []byte(canary), 0o600, AtomicWriteOptions{})
	e = wantStatus(t, err, coreerr.StatusInternalFailure)
	if strings.Contains(e.Message, canary) || !strings.Contains(e.Message, "Could not replace") {
		t.Errorf("message %q", e.Message)
	}
	if len(strayTempFiles(t, dir)) != 0 {
		t.Errorf("stray temp: %v", strayTempFiles(t, dir))
	}
}

// Swift: FileEditTests.swift "a symlinked settings file stays a symlink and the target is written"
func TestSymlinkedTargetStaysALink(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	target := filepath.Join(dir, "shared", "settings.json")
	writeFile(t, target, "{}\n", 0o600)
	link := filepath.Join(dir, ".claude", "settings.json")
	if err := os.MkdirAll(filepath.Dir(link), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	resolved, err := ResolveTarget(link)
	if err != nil {
		t.Fatal(err)
	}
	if resolved.Real != target || !resolved.Existed || resolved.Mode != 0o600 {
		t.Fatalf("resolved %+v", resolved)
	}
	if err := AtomicWrite(resolved.Real, []byte("{\"Read\":1}\n"), resolved.Mode, AtomicWriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if dest, err := os.Readlink(link); err != nil || dest != target {
		t.Errorf("link now %q, %v", dest, err)
	}
	if readFile(t, target) != "{\"Read\":1}\n" || modeOf(t, target) != 0o600 {
		t.Errorf("target %q mode %o", readFile(t, target), modeOf(t, target))
	}
	if len(strayTempFiles(t, filepath.Dir(link), filepath.Dir(target))) != 0 {
		t.Error("stray temp file")
	}
}

// Swift: FileEditTests.swift "a link to nothing is refused instead of being replaced"
func TestDanglingLinkRefused(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	link := filepath.Join(dir, "settings.json")
	if err := os.Symlink(filepath.Join(dir, "missing.json"), link); err != nil {
		t.Fatal(err)
	}
	_, err := ResolveTarget(link)
	wantStatus(t, err, coreerr.StatusConflict)
	if _, err := os.Readlink(link); err != nil {
		t.Error("the link was replaced")
	}
}

func TestResolveTargetNotARegularFile(t *testing.T) {
	dir := tempDir(t)
	_, err := ResolveTarget(dir)
	wantStatus(t, err, coreerr.StatusConflict)
}

// Swift: FileEditTests.swift "a missing file is created with mode 0600, and undo moves it to the trash" (create part)
func TestMissingTargetIsCreatedWith0600(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	path := filepath.Join(dir, "proj", ".claude", "settings.local.json")
	resolved, err := ResolveTarget(path)
	if err != nil {
		t.Fatal(err)
	}
	if resolved.Existed || resolved.Real != path || resolved.Mode != NewFileMode {
		t.Fatalf("resolved %+v", resolved)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := AtomicWrite(resolved.Real, []byte("{}\n"), resolved.Mode, AtomicWriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if modeOf(t, path) != 0o600 {
		t.Errorf("mode %o", modeOf(t, path))
	}
}

// Swift: WriteConcurrencyTests.swift "a file changed by someone else between the read and the rename is left alone (409)"
func TestExternalChangeBeforeRename(t *testing.T) {
	dir := tempDir(t)
	file := filepath.Join(dir, "settings.json")
	writeFile(t, file, "{\n  \"model\": \"mine\"\n}\n", 0o600)
	before := []byte(readFile(t, file))
	conflict := coreerr.NewStatus(file+" changed while SpaceVibe was editing it, so it was left alone. Try again.", coreerr.StatusConflict)
	err := AtomicWrite(file, []byte("{\n  \"model\": \"next\"\n}\n"), 0o600, AtomicWriteOptions{
		// Validate runs on the temp file, after the read and before the rename: write the target from "another process".
		Validate: func([]byte) error { return os.WriteFile(file, []byte("{\"model\":\"theirs\"}\n"), 0o600) },
		BeforeRename: func() error {
			if !UnchangedSince(file, before) {
				return conflict
			}
			return nil
		},
	})
	wantStatus(t, err, coreerr.StatusConflict)
	if readFile(t, file) != "{\"model\":\"theirs\"}\n" || len(strayTempFiles(t, dir)) != 0 {
		t.Errorf("target %q stray %v", readFile(t, file), strayTempFiles(t, dir))
	}
}

// Swift: WriteConcurrencyTests.swift "a file created by someone else while a new file is being written is left alone (409)"
func TestExternalCreateBeforeRename(t *testing.T) {
	dir := tempDir(t)
	file := filepath.Join(dir, ".claude", "settings.json")
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		t.Fatal(err)
	}
	conflict := coreerr.NewStatus("changed", coreerr.StatusConflict)
	err := AtomicWrite(file, []byte("{\"model\":\"x\"}\n"), 0o600, AtomicWriteOptions{
		Validate: func([]byte) error { return os.WriteFile(file, []byte("{}\n"), 0o600) },
		BeforeRename: func() error {
			if !UnchangedSince(file, nil) {
				return conflict
			}
			return nil
		},
	})
	wantStatus(t, err, coreerr.StatusConflict)
	if readFile(t, file) != "{}\n" || len(strayTempFiles(t, filepath.Dir(file))) != 0 {
		t.Errorf("target %q stray %v", readFile(t, file), strayTempFiles(t, filepath.Dir(file)))
	}
}

func TestUnchangedSince(t *testing.T) {
	dir := tempDir(t)
	file := filepath.Join(dir, "f")
	if !UnchangedSince(file, nil) {
		t.Error("a missing file with before == nil is unchanged")
	}
	if UnchangedSince(file, []byte("x")) {
		t.Error("a deleted file is a change")
	}
	writeFile(t, file, "", 0o600)
	if UnchangedSince(file, nil) {
		t.Error("an existing empty file is not 'still absent'")
	}
	if !UnchangedSince(file, []byte{}) {
		t.Error("an empty file equals an empty non-nil before")
	}
	writeFile(t, file, "abc", 0o600)
	if !UnchangedSince(file, []byte("abc")) || UnchangedSince(file, []byte("abd")) {
		t.Error("byte comparison wrong")
	}
	// A directory cannot be read as a file: changed, even for nil.
	if UnchangedSince(dir, nil) {
		t.Error("an unreadable existing path must count as changed")
	}
}

// Swift: FileEditTests.swift "text edit keeps bytes that Swift string equality would treat as equal"
func TestAtomicWriteKeepsCanonicallyEquivalentBytes(t *testing.T) {
	dir := tempDir(t)
	file := filepath.Join(dir, "notes.txt")
	precomposed, decomposed := "café\n", "café\n"
	writeFile(t, file, precomposed, 0o600)
	if UnchangedSince(file, []byte(decomposed)) {
		t.Fatal("NFC and NFD bytes must compare different")
	}
	if err := AtomicWrite(file, []byte(decomposed), 0o600, AtomicWriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if readFile(t, file) != decomposed {
		t.Errorf("bytes %q", readFile(t, file))
	}
}

// Swift: WriteConcurrencyTests.swift "writers next to one target never share a temp file (the lock is not what protects this)"
func TestConcurrentWritersNeverShareATempFile(t *testing.T) {
	dir := tempDir(t)
	target := filepath.Join(dir, "file.txt")
	var wg sync.WaitGroup
	errs := make(chan error, 50)
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs <- AtomicWrite(target, []byte(fmt.Sprintf("writer %d\n", i)), 0o600, AtomicWriteOptions{})
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Error(err)
		}
	}
	text := readFile(t, target)
	if !strings.HasPrefix(text, "writer ") || !strings.HasSuffix(text, "\n") {
		t.Errorf("target %q", text)
	}
	if len(strayTempFiles(t, dir)) != 0 {
		t.Errorf("stray %v", strayTempFiles(t, dir))
	}
}

// G-fix.6: only ENOENT/ENOTDIR mean "absent"; any other stat failure is a 409, not a new file.
func TestResolveTargetOnlyAbsentMeansAbsent(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	if got, err := ResolveTarget(filepath.Join(dir, "missing.json")); err != nil || got.Existed {
		t.Errorf("ENOENT: %+v %v", got, err)
	}
	file := filepath.Join(dir, "plain")
	writeFile(t, file, "x", 0o600)
	if got, err := ResolveTarget(filepath.Join(file, "under-a-file")); err != nil || got.Existed {
		t.Errorf("ENOTDIR: %+v %v", got, err)
	}

	// Permission denied on the parent folder.
	locked := filepath.Join(dir, "locked")
	writeFile(t, filepath.Join(locked, "settings.json"), canary, 0o600)
	if err := os.Chmod(locked, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o700) })
	if _, err := os.Stat(filepath.Join(locked, "settings.json")); err == nil {
		t.Skip("running as a user that ignores folder permissions")
	}
	_, err := ResolveTarget(filepath.Join(locked, "settings.json"))
	e := wantStatus(t, err, coreerr.StatusConflict)
	if !strings.HasSuffix(e.Message, " could not be checked, so it was left alone.") || strings.Contains(e.Message, canary) {
		t.Error(e.Message)
	}

	// A link loop (ELOOP) is not absent either.
	a, b := filepath.Join(dir, "loop-a"), filepath.Join(dir, "loop-b")
	if err := os.Symlink(b, a); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(a, b); err != nil {
		t.Fatal(err)
	}
	_, err = ResolveTarget(a)
	wantStatus(t, err, coreerr.StatusConflict)
}
