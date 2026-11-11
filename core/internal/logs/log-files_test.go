package logs

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// Swift: LogFilesTests.swift "naming: which names are logs, and the shared base name of both forms"
func TestNaming(t *testing.T) {
	for name, want := range map[string]bool{
		"a.jsonl": true, "a.jsonl.zst": true, "a.jsonl.zstd": true,
		"a.json": false, "a.zst": false, "a.jsonl.bak": false, "a.jsonl.zst.tmp": false,
	} {
		if got := IsLog(name); got != want {
			t.Errorf("IsLog(%q) = %v, want %v", name, got, want)
		}
	}
	if BaseName("/x/rollout-1.jsonl") != "rollout-1" || BaseName("/x/rollout-1.jsonl.zst") != "rollout-1" {
		t.Error("both forms must share the base name rollout-1")
	}
	if !IsCompressed("/x/rollout-1.jsonl.zst") || !IsCompressed("/x/a.jsonl.zstd") || IsCompressed("/x/rollout-1.jsonl") {
		t.Error("IsCompressed wrong")
	}
	if BaseName("/x/notes.txt") != "notes.txt" {
		t.Error("a name without a log suffix is its own base name")
	}
}

func relativeTo(root string, paths []string) []string {
	out := []string{}
	for _, p := range paths {
		out = append(out, strings.TrimPrefix(p, root+string(filepath.Separator)))
	}
	return out
}

// Swift: LogFilesTests.swift "walk finds both forms, lists only the plain one when both exist, ignores symlinks and other files"
func TestWalk(t *testing.T) {
	home := resolvedTempDir(t)
	zst := fixture(t, "zst/small.jsonl.zst")
	writeFile(t, home, "logs/a.jsonl", []byte("{}\n"))
	writeFile(t, home, "logs/a.jsonl.zst", zst)
	writeFile(t, home, "logs/b.jsonl.zst", zst)
	writeFile(t, home, "logs/2026/11/c.jsonl", []byte("{}\n"))
	writeFile(t, home, "logs/notes.txt", []byte("x"))
	writeFile(t, home, "logs/d.json", []byte("{}"))
	writeFile(t, home, "logs/.hidden.jsonl", []byte("{}\n"))
	writeFile(t, home, "elsewhere/e.jsonl", []byte("{}\n"))
	if err := os.Symlink(filepath.Join(home, "elsewhere/e.jsonl"), filepath.Join(home, "logs/link.jsonl")); err != nil {
		t.Skip("symlinks unavailable:", err)
	}
	if err := os.Symlink(filepath.Join(home, "elsewhere"), filepath.Join(home, "logs/linkdir")); err != nil {
		t.Fatal(err)
	}

	logs := filepath.Join(home, "logs")
	got := relativeTo(logs, Walk(logs))
	want := []string{".hidden.jsonl", filepath.Join("2026", "11", "c.jsonl"), "a.jsonl", "b.jsonl.zst"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("walk = %v, want %v", got, want)
	}
	if missing := Walk(filepath.Join(home, "missing")); len(missing) != 0 {
		t.Errorf("walk of a missing folder = %v, want empty", missing)
	}
}

// Swift: ReadHardeningTests.swift "walk returns paths under the folder as given, even when that folder is a symlink"
func TestWalkKeepsGivenBase(t *testing.T) {
	home := resolvedTempDir(t)
	real := filepath.Join(home, "dotfiles", "claude")
	writeFile(t, home, "dotfiles/claude/projects/-p/s1.jsonl", []byte("{}\n"))
	link := filepath.Join(home, "linked-claude")
	if err := os.Symlink(real, link); err != nil {
		t.Skip("symlinks unavailable:", err)
	}
	got := Walk(filepath.Join(link, "projects"))
	want := []string{filepath.Join(link, "projects", "-p", "s1.jsonl")}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("walk = %v, want %v", got, want)
	}
}

func collectLines(t *testing.T, path string, maxLine int) ([]string, int) {
	t.Helper()
	var lines []string
	skipped, err := ForEachLine(path, maxLine, func(line []byte) error {
		lines = append(lines, string(line))
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return lines, skipped
}

// Swift: LogFilesTests.swift "forEachLine reads plain and compressed logs the same, including a last line without a newline"
func TestForEachLinePlainAndCompressed(t *testing.T) {
	dir := t.TempDir()
	plain := writeFile(t, dir, "p.jsonl", []byte("{\"a\":1}\n\n{\"b\":\"é\"}\n{\"c\":3}"))
	got, _ := collectLines(t, plain, 0)
	if want := []string{`{"a":1}`, "", `{"b":"é"}`, `{"c":3}`}; !reflect.DeepEqual(got, want) {
		t.Errorf("plain lines = %q, want %q", got, want)
	}

	small := string(fixture(t, "zst/small.jsonl"))
	fromZst, _ := collectLines(t, fixturePath("zst/small.jsonl.zst"), 0)
	want := strings.Split(small, "\n")
	want = want[:len(want)-1]
	if !reflect.DeepEqual(fromZst, want) {
		t.Errorf("compressed lines = %q, want %q", fromZst, want)
	}
}

// Swift: LogFilesTests.swift "forEachLine on the 5.5 MB compressed log yields every line once, intact across chunk boundaries"
func TestForEachLineLarge(t *testing.T) {
	meta := largeMeta(t)
	count, broken := 0, 0
	_, err := ForEachLine(fixturePath("zst/large.jsonl.zst"), 0, func(line []byte) error {
		count++
		if len(line) == 0 || line[0] != '{' || line[len(line)-1] != '}' {
			broken++
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if count != meta.Lines || broken != 0 {
		t.Errorf("lines = %d (want %d), broken = %d", count, meta.Lines, broken)
	}
}

// Swift: LogFilesTests.swift "a line over the cap is skipped and counted; the lines around it survive"
func TestForEachLineCap(t *testing.T) {
	big := `{"x":"` + strings.Repeat("y", 5_000) + `"}`
	file := writeFile(t, t.TempDir(), "c.jsonl", []byte(`{"a":1}`+"\n"+big+"\n"+`{"b":2}`+"\n"+big))
	got, skipped := collectLines(t, file, 1_000)
	if want := []string{`{"a":1}`, `{"b":2}`}; !reflect.DeepEqual(got, want) {
		t.Errorf("lines = %q, want %q", got, want)
	}
	if skipped != 2 {
		t.Errorf("skipped = %d, want 2", skipped)
	}
}

// Swift: LogFilesTests.swift "the reader factory picks the class from the extension"
func TestNewReaderPicksByExtension(t *testing.T) {
	if _, ok := NewReader("/x/a.jsonl", 0).(*TailReader); !ok {
		t.Error("a .jsonl path must get a TailReader")
	}
	if _, ok := NewReader("/x/a.jsonl.zst", 0).(*CompressedLogReader); !ok {
		t.Error("a .jsonl.zst path must get a CompressedLogReader")
	}
}

// Trap: bufio.Scanner stops at 64 KB; the line limit here is 32 MiB (UsageScanner.maxLineBytes).
func TestForEachLineLongerThanScannerLimit(t *testing.T) {
	const size = 33 << 20 // over 32 MiB
	line := `{"x":"` + strings.Repeat("y", 3<<20) + `"}`
	file := writeFile(t, t.TempDir(), "long.jsonl", []byte(line+"\n"+`{"b":2}`+"\n"))
	var lengths []int
	_, err := ForEachLine(file, 32<<20, func(l []byte) error { lengths = append(lengths, len(l)); return nil })
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(lengths, []int{len(line), 7}) {
		t.Errorf("lengths = %v, want [%d 7]", lengths, len(line))
	}
	// And a line past the 32 MiB cap is skipped and counted, not truncated.
	over := bytes.Repeat([]byte("z"), size)
	file = writeFile(t, t.TempDir(), "over.jsonl", append(append(append([]byte(`{"a":1}`+"\n"), over...), '\n'), []byte(`{"b":2}`+"\n")...))
	got, skipped := collectLines(t, file, 32<<20)
	if !reflect.DeepEqual(got, []string{`{"a":1}`, `{"b":2}`}) || skipped != 1 {
		t.Errorf("got %d lines, skipped %d", len(got), skipped)
	}
}

func TestForEachChunkBodyErrorStops(t *testing.T) {
	stop := errors.New("stop")
	file := writeFile(t, t.TempDir(), "p.jsonl", []byte("{}\n"))
	calls := 0
	err := ForEachChunk(file, func([]byte) error { calls++; return stop })
	if err != stop || calls != 1 {
		t.Errorf("err = %v, calls = %d", err, calls)
	}
}

func TestForEachChunkMissingPlainFile(t *testing.T) {
	err := ForEachChunk(filepath.Join(t.TempDir(), "none.jsonl"), func([]byte) error { return nil })
	var readErr *ReadError
	if !errors.As(err, &readErr) || readErr.Errno == 0 {
		t.Fatalf("err = %v, want a ReadError with an errno", err)
	}
}

func TestForEachChunkEmptyFile(t *testing.T) {
	file := writeFile(t, t.TempDir(), "empty.jsonl", nil)
	calls := 0
	if err := ForEachChunk(file, func([]byte) error { calls++; return nil }); err != nil || calls != 0 {
		t.Fatalf("err = %v, calls = %d, want no error or chunks", err, calls)
	}
}

// The initial size is only a buffer hint: bytes appended before EOF must still be read.
func TestForEachChunkReadsAppendedData(t *testing.T) {
	initial := []byte("{}\n")
	file := writeFile(t, t.TempDir(), "growing.jsonl", initial)
	extra := bytes.Repeat([]byte("x"), 2*plainReadChunk+17)
	var got []byte
	err := ForEachChunk(file, func(chunk []byte) error {
		first := len(got) == 0
		got = append(got, chunk...)
		if !first {
			return nil
		}
		f, err := os.OpenFile(file, os.O_APPEND|os.O_WRONLY, 0)
		if err != nil {
			return err
		}
		_, writeErr := f.Write(extra)
		closeErr := f.Close()
		return errors.Join(writeErr, closeErr)
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := append(initial, extra...); !bytes.Equal(got, want) {
		t.Fatalf("read %d bytes, want all %d original and appended bytes", len(got), len(want))
	}
}

func BenchmarkForEachChunkPlain(b *testing.B) {
	for _, tc := range []struct {
		name string
		size int
	}{
		{"small-512B", 512},
		{"medium-64KiB", 64 << 10},
		{"large-8MiB", 8 << 20},
	} {
		b.Run(tc.name, func(b *testing.B) {
			file := filepath.Join(b.TempDir(), "session.jsonl")
			if err := os.WriteFile(file, bytes.Repeat([]byte("x"), tc.size), 0o600); err != nil {
				b.Fatal(err)
			}
			b.SetBytes(int64(tc.size))
			b.ReportAllocs()
			b.ResetTimer()
			for b.Loop() {
				read := 0
				err := ForEachChunk(file, func(chunk []byte) error { read += len(chunk); return nil })
				if err != nil || read != tc.size {
					b.Fatalf("read %d bytes, err = %v; want %d bytes", read, err, tc.size)
				}
			}
		})
	}
}
