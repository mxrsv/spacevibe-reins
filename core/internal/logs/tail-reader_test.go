package logs

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
)

type tailRead struct {
	lines  []string
	result ReadResult
	resets int
}

func readAll(t *testing.T, r LogReader) tailRead {
	t.Helper()
	out := tailRead{lines: []string{}}
	result, err := r.Read(func(line []byte) { out.lines = append(out.lines, string(line)) }, func() { out.resets++ })
	if err != nil {
		t.Fatal(err)
	}
	out.result = result
	return out
}

func appendTo(t *testing.T, path, text string) {
	t.Helper()
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err := f.WriteString(text); err != nil {
		t.Fatal(err)
	}
}

func equalLines(t *testing.T, got, want []string) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Errorf("lines = %q, want %q", got, want)
	}
}

// Swift: TailReaderTests.swift "a second read returns only what was appended; a half-written line waits for its newline"
func TestTailIncremental(t *testing.T) {
	file := writeFile(t, t.TempDir(), "s.jsonl", []byte("{\"n\":1}\n{\"n\":2}\n{\"n\":"))
	r := NewTailReader(file, TailOptions{})
	first := readAll(t, r)
	equalLines(t, first.lines, []string{`{"n":1}`, `{"n":2}`})
	if first.result.Lines != 2 || first.result.Size != 21 {
		t.Errorf("lines = %d size = %d, want 2 and 21", first.result.Lines, first.result.Size)
	}
	if first.result.Modified.IsZero() {
		t.Error("modified must be set")
	}
	if again := readAll(t, r); len(again.lines) != 0 {
		t.Errorf("second read = %q, want nothing", again.lines)
	}
	appendTo(t, file, "3}\n{\"n\":4}\n")
	second := readAll(t, r)
	equalLines(t, second.lines, []string{`{"n":3}`, `{"n":4}`})
	if second.resets != 0 {
		t.Errorf("resets = %d", second.resets)
	}
	data, _ := os.ReadFile(file)
	if r.Offset() != int64(len(data)) {
		t.Errorf("offset = %d, want %d", r.Offset(), len(data))
	}
}

// Swift: TailReaderTests.swift "a file that shrank is read again from the start, with onReset"
func TestTailTruncation(t *testing.T) {
	file := writeFile(t, t.TempDir(), "t.jsonl", []byte("{\"a\":1}\n{\"a\":2}\n{\"a\":3}\n"))
	r := NewTailReader(file, TailOptions{})
	readAll(t, r)
	if err := os.WriteFile(file, []byte("{\"b\":1}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	again := readAll(t, r)
	equalLines(t, again.lines, []string{`{"b":1}`})
	if again.resets != 1 || !again.result.DidReset {
		t.Errorf("resets = %d didReset = %v", again.resets, again.result.DidReset)
	}
}

// Swift: TailReaderTests.swift "a file replaced by another (new inode), even a longer one, is read again from the start"
func TestTailReplacedInode(t *testing.T) {
	dir := t.TempDir()
	file := writeFile(t, dir, "r.jsonl", []byte("{\"a\":1}\n"))
	r := NewTailReader(file, TailOptions{})
	equalLines(t, readAll(t, r).lines, []string{`{"a":1}`})
	replacement := writeFile(t, dir, "r-new.jsonl", []byte("{\"z\":9}\n{\"z\":8}\n{\"z\":7}\n"))
	if err := os.Rename(replacement, file); err != nil {
		t.Fatal(err)
	}
	again := readAll(t, r)
	if again.resets != 1 {
		t.Errorf("resets = %d, want 1", again.resets)
	}
	equalLines(t, again.lines, []string{`{"z":9}`, `{"z":8}`, `{"z":7}`})
}

// Swift: TailReaderTests.swift "a missing file reports missing, then reads once it appears"
func TestTailMissing(t *testing.T) {
	dir := t.TempDir()
	r := NewTailReader(filepath.Join(dir, "later.jsonl"), TailOptions{})
	none := readAll(t, r)
	if !none.result.Missing || len(none.lines) != 0 {
		t.Errorf("result = %+v lines = %q", none.result, none.lines)
	}
	writeFile(t, dir, "later.jsonl", []byte("{\"a\":1}\n"))
	equalLines(t, readAll(t, r).lines, []string{`{"a":1}`})
}

// Swift: TailReaderTests.swift "maxBytes starts late and drops the cut line"
func TestTailMaxBytes(t *testing.T) {
	var body strings.Builder
	for n := 1; n <= 50; n++ {
		body.WriteString(`{"n":` + itoa(n) + "}\n")
	}
	file := writeFile(t, t.TempDir(), "m.jsonl", []byte(body.String()))
	read := readAll(t, NewTailReader(file, TailOptions{MaxBytes: 40}))
	if !read.result.Truncated {
		t.Error("result must be truncated")
	}
	if read.lines[len(read.lines)-1] != `{"n":50}` {
		t.Errorf("last = %q", read.lines[len(read.lines)-1])
	}
	if len(read.lines) < 3 || len(read.lines) > 5 {
		t.Errorf("count = %d, want 3...5", len(read.lines))
	}
	for _, line := range read.lines {
		if line == `{"n":1}` || !strings.HasPrefix(line, "{") || !strings.HasSuffix(line, "}") {
			t.Errorf("line %q is not a whole later line", line)
		}
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var digits []byte
	for ; n > 0; n /= 10 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
	}
	return string(digits)
}

// Swift: TailReaderTests.swift "an over-long line is skipped and counted, and the next lines still arrive"
func TestTailLineCap(t *testing.T) {
	big := `{"x":"` + strings.Repeat("y", 3_000) + `"}`
	file := writeFile(t, t.TempDir(), "c.jsonl", []byte(`{"a":1}`+"\n"+big+"\n"+`{"b":2}`+"\n"))
	r := NewTailReader(file, TailOptions{MaxLineBytes: 500})
	read := readAll(t, r)
	equalLines(t, read.lines, []string{`{"a":1}`, `{"b":2}`})
	if read.result.OversizedLines != 1 || r.OversizedLines() != 1 {
		t.Errorf("oversized = %d / %d, want 1", read.result.OversizedLines, r.OversizedLines())
	}
}

// Swift: TailReaderTests.swift "a line that grows past the cap across reads is dropped once, whole"
func TestTailCapAcrossReads(t *testing.T) {
	file := writeFile(t, t.TempDir(), "g.jsonl", []byte(`{"a":1}`+"\n"+`{"x":"`+strings.Repeat("y", 2_000)))
	r := NewTailReader(file, TailOptions{MaxLineBytes: 500})
	readAll(t, r)
	appendTo(t, file, strings.Repeat("z", 100)+"\"}\n{\"b\":2}\n")
	next := readAll(t, r)
	equalLines(t, next.lines, []string{`{"b":2}`})
	if r.OversizedLines() != 1 {
		t.Errorf("oversized = %d, want 1", r.OversizedLines())
	}
}

// Swift: TailReaderTests.swift "lines that are not objects are counted, blank lines are not"
func TestTailInvalidLines(t *testing.T) {
	file := writeFile(t, t.TempDir(), "i.jsonl", []byte("{\"a\":1}\nnot json at all\n\n   \n[1,2]\n{\"b\":2}\n\"str\"\n"))
	r := NewTailReader(file, TailOptions{})
	read := readAll(t, r)
	equalLines(t, read.lines, []string{`{"a":1}`, `{"b":2}`})
	if read.result.InvalidLines != 3 || r.InvalidLines() != 3 {
		t.Errorf("invalid = %d / %d, want 3", read.result.InvalidLines, r.InvalidLines())
	}
	r.NoteInvalidLine()
	if r.InvalidLines() != 4 {
		t.Errorf("after NoteInvalidLine: %d, want 4", r.InvalidLines())
	}
	if again := readAll(t, r); again.result.InvalidLines != 0 {
		t.Errorf("a read with nothing new added %d", again.result.InvalidLines)
	}
}

// Swift: TailReaderTests.swift "with the shape check off, any non-blank line passes"
func TestTailShapeCheckOff(t *testing.T) {
	file := writeFile(t, t.TempDir(), "o.jsonl", []byte("plain text\n\n[1]\n"))
	equalLines(t, readAll(t, NewTailReader(file, TailOptions{AnyLineShape: true})).lines, []string{"plain text", "[1]"})
}

// Swift: TailReaderTests.swift "multi-byte characters survive chunk boundaries"
func TestTailMultibyte(t *testing.T) {
	row := `{"t":"` + strings.Repeat("é🙂", 60_000) + `"}`
	file := writeFile(t, t.TempDir(), "u.jsonl", []byte(row+"\n"+row+"\n"+row+"\n"))
	equalLines(t, readAll(t, NewTailReader(file, TailOptions{})).lines, []string{row, row, row})
}

// Swift: TailReaderTests.swift "an unreadable file throws an error that carries only errno"
func TestTailUnreadable(t *testing.T) {
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("permission bits are not enforced here")
	}
	file := writeFile(t, t.TempDir(), "p.jsonl", []byte("{\"a\":1}\n"))
	if err := os.Chmod(file, 0); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(file, 0o600)
	_, err := NewTailReader(file, TailOptions{}).Read(func([]byte) {}, nil)
	var readErr *ReadError
	if !errors.As(err, &readErr) {
		t.Fatalf("err = %v, want a ReadError", err)
	}
	if strings.Contains(err.Error(), file) {
		t.Errorf("error names the path: %q", err)
	}
}

// Extra: a CRLF file keeps the trailing CR on the line passed, and the shape check ignores it.
func TestTailKeepsCarriageReturn(t *testing.T) {
	file := writeFile(t, t.TempDir(), "crlf.jsonl", []byte("{\"a\":1}\r\n{\"b\":2}\r\n"))
	equalLines(t, readAll(t, NewTailReader(file, TailOptions{})).lines, []string{"{\"a\":1}\r", "{\"b\":2}\r"})
}

// Extra: a directory is refused with a ReadError or ErrNotRegular, never read.
func TestTailDirectoryIsRefused(t *testing.T) {
	_, err := NewTailReader(t.TempDir(), TailOptions{}).Read(func([]byte) {}, nil)
	if !errors.Is(err, ErrNotRegular) {
		t.Fatalf("err = %v, want ErrNotRegular", err)
	}
}

// Extra: a callback that keeps a line must copy it; this documents that the slice is reused across lines.
func TestTailLineIsOnlyValidDuringCallback(t *testing.T) {
	file := writeFile(t, t.TempDir(), "k.jsonl", []byte("{\"a\":1}\n{\"b\":2}\n"))
	var kept [][]byte
	_, err := NewTailReader(file, TailOptions{}).Read(func(l []byte) { kept = append(kept, append([]byte(nil), l...)) }, nil)
	if err != nil || len(kept) != 2 || string(kept[0]) != `{"a":1}` {
		t.Fatalf("copied lines = %q err = %v", kept, err)
	}
}
