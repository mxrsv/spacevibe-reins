package logs

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Swift: TailReaderTests.swift "reads a .zst log once, then nothing until the file changes"
func TestCompressedReadsOnce(t *testing.T) {
	dir := t.TempDir()
	file := writeFile(t, dir, "a.jsonl.zst", fixture(t, "zst/small.jsonl.zst"))
	r := NewCompressedLogReader(file, CompressedOptions{})
	first := readAll(t, r)
	if len(first.lines) != 3 || first.result.Lines != 3 {
		t.Fatalf("first read = %d lines (result %d), want 3", len(first.lines), first.result.Lines)
	}
	second := readAll(t, r)
	if len(second.lines) != 0 || second.result.DidReset {
		t.Errorf("second read = %q reset %v, want nothing", second.lines, second.result.DidReset)
	}

	if err := os.WriteFile(file, fixture(t, "zst/twice.jsonl.zst"), 0o644); err != nil {
		t.Fatal(err)
	}
	third := readAll(t, r)
	if third.resets != 1 || !third.result.DidReset || len(third.lines) != 6 {
		t.Errorf("third read: resets %d didReset %v lines %d, want 1 true 6", third.resets, third.result.DidReset, len(third.lines))
	}
}

// Swift: TailReaderTests.swift "maxBytes keeps the last lines of the log"
func TestCompressedTail(t *testing.T) {
	r := NewCompressedLogReader(fixturePath("zst/large.jsonl.zst"), CompressedOptions{MaxBytes: 4_000})
	read := readAll(t, r)
	if !read.result.Truncated {
		t.Error("must be truncated")
	}
	if len(read.lines) <= 5 || len(read.lines) >= 80 {
		t.Errorf("lines = %d, want 6...79", len(read.lines))
	}
	want := `{"i":` + strconv.Itoa(largeMeta(t).Lines-1) + `,`
	if last := read.lines[len(read.lines)-1]; !strings.HasPrefix(last, want) {
		t.Errorf("last line %q does not start with %q", last, want)
	}
}

// Swift: TailReaderTests.swift "a truncated archive surfaces ZstdError.truncated and a missing one reports missing"
func TestCompressedErrors(t *testing.T) {
	dir := t.TempDir()
	full := fixture(t, "zst/cli-made.jsonl.zst")
	cut := writeFile(t, dir, "cut.jsonl.zst", full[:len(full)/2])
	if _, err := NewCompressedLogReader(cut, CompressedOptions{}).Read(func([]byte) {}, nil); !errors.Is(err, ErrTruncated) {
		t.Errorf("err = %v, want ErrTruncated", err)
	}
	missing, err := NewCompressedLogReader(filepath.Join(dir, "none.jsonl.zst"), CompressedOptions{}).Read(func([]byte) {}, nil)
	if err != nil || !missing.Missing {
		t.Errorf("missing = %+v err = %v", missing, err)
	}
}

// Swift: ReadHardeningTests.swift "a stream of 200000 short lines is read with only about maxBytes of lines held"
func TestCompressedRingBufferBoundsMemory(t *testing.T) {
	var text strings.Builder
	for n := 0; n < 200_000; n++ {
		text.WriteString(`{"i":` + strconv.Itoa(n) + "}\n")
	}
	file := writeFile(t, t.TempDir(), "many.jsonl.zst", zstdRaw([]byte(text.String())))
	r := NewCompressedLogReader(file, CompressedOptions{MaxBytes: 10_000})
	read := readAll(t, r)
	if !read.result.Truncated {
		t.Error("must be truncated")
	}
	if last := read.lines[len(read.lines)-1]; last != `{"i":199999}` {
		t.Errorf("last = %q", last)
	}
	if len(read.lines) <= 500 || len(read.lines) >= 1000 {
		t.Errorf("lines = %d, want 501...999", len(read.lines))
	}
	if read.result.Lines != len(read.lines) {
		t.Errorf("result.Lines = %d, lines = %d", read.result.Lines, len(read.lines))
	}
	if r.peakStoredLines >= 4000 {
		t.Errorf("held %d lines at the peak out of 200000", r.peakStoredLines)
	}
}

// Swift: ReadHardeningTests.swift "LineTail keeps at least one line and drops the oldest first"
func TestLineTailKeepsOneLine(t *testing.T) {
	tail := newLineTail(10)
	tail.append(bytesOf(0x61, 50))
	if tail.count() != 1 || tail.dropped {
		t.Fatalf("count = %d dropped = %v, want 1 false", tail.count(), tail.dropped)
	}
	tail.append(bytesOf(0x62, 4))
	tail.append(bytesOf(0x63, 4))
	var sizes []int
	tail.forEach(func(l []byte) { sizes = append(sizes, len(l)) })
	if len(sizes) != 2 || sizes[0] != 4 || sizes[1] != 4 || !tail.dropped || tail.bytes != 8 {
		t.Errorf("sizes = %v dropped = %v bytes = %d", sizes, tail.dropped, tail.bytes)
	}
}

func bytesOf(b byte, n int) []byte { return []byte(strings.Repeat(string([]byte{b}), n)) }

// Swift: ReadHardeningTests.swift "a dropped line over the length cap marks the read truncated"
func TestCompressedOversizedLineIsTruncated(t *testing.T) {
	long := `{"x":"` + strings.Repeat("a", 300) + `"}` + "\n"
	file := writeFile(t, t.TempDir(), "long.jsonl.zst", zstdRaw([]byte(long+`{"a":1}`+"\n")))
	read := readAll(t, NewCompressedLogReader(file, CompressedOptions{MaxLineBytes: 100}))
	if len(read.lines) != 1 || read.result.OversizedLines != 1 || !read.result.Truncated {
		t.Errorf("lines %d oversized %d truncated %v", len(read.lines), read.result.OversizedLines, read.result.Truncated)
	}
}

// Swift: ReadHardeningTests.swift "the default cap stops a 600 MB expansion for the reader, and a second poll of the
// same file fails at once"
func TestCompressedDefaultCapAndSecondPoll(t *testing.T) {
	file := writeFile(t, t.TempDir(), "bomb.jsonl.zst", zstdRepeated(0x78, 600*1024*1024))
	r := NewCompressedLogReader(file, CompressedOptions{})
	if _, err := r.Read(func([]byte) {}, nil); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("first read: err = %v, want ErrTooLarge", err)
	}
	again := time.Now()
	if _, err := r.Read(func([]byte) {}, nil); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("second read: err = %v, want ErrTooLarge", err)
	}
	if elapsed := time.Since(again); elapsed > 500*time.Millisecond {
		t.Errorf("the same unchanged file was decompressed again (%s)", elapsed)
	}
}

// Extra: lines that are not objects in a compressed log are counted, blank lines are not.
func TestCompressedInvalidLines(t *testing.T) {
	file := writeFile(t, t.TempDir(), "i.jsonl.zst", zstdRaw([]byte("{\"a\":1}\nnot json\n\n[1]\n{\"b\":2}\n")))
	r := NewCompressedLogReader(file, CompressedOptions{})
	read := readAll(t, r)
	equalLines(t, read.lines, []string{`{"a":1}`, `{"b":2}`})
	if read.result.InvalidLines != 2 || r.InvalidLines() != 2 {
		t.Errorf("invalid = %d / %d, want 2", read.result.InvalidLines, r.InvalidLines())
	}
	r.NoteInvalidLine()
	if r.InvalidLines() != 3 {
		t.Errorf("after NoteInvalidLine: %d", r.InvalidLines())
	}
}
