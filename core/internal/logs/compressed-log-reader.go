package logs

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
)

// fileStamp is what says a compressed log changed: identity, size and mtime.
type fileStamp struct{ info os.FileInfo }

func (s fileStamp) same(other fileStamp) bool {
	return s.info != nil && other.info != nil && os.SameFile(s.info, other.info) &&
		s.info.Size() == other.info.Size() && s.info.ModTime().Equal(other.info.ModTime())
}

// CompressedOptions configure a CompressedLogReader. The zero value is the default.
type CompressedOptions struct {
	// MaxBytes keeps the last lines up to about this many bytes, as TailReader does by starting late. 0 or less: all.
	MaxBytes int64
	// MaxLineBytes: longer lines are skipped. 0 or less means DefaultMaxLineBytes.
	MaxLineBytes int
}

// CompressedLogReader is the same Read for a `.zst` log. It cannot seek or be appended to, so it reads the whole file
// once and again only when the file changes (identity, size or mtime), calling onReset before the second full read.
// MaxBytes counts bytes, like TailReader. It is not safe for concurrent use.
type CompressedLogReader struct {
	path         string
	maxBytes     int64
	maxLineBytes int

	invalidLines  int
	stamp         fileStamp
	tooLargeStamp fileStamp
	truncated     bool
	// peakStoredLines is the most lines held at once during the last full read: bounded by MaxBytes, not by the
	// file's line count.
	peakStoredLines int
}

// NewCompressedLogReader returns a reader for the `.zst` file at path.
func NewCompressedLogReader(path string, opts CompressedOptions) *CompressedLogReader {
	maxLine := opts.MaxLineBytes
	if maxLine <= 0 {
		maxLine = DefaultMaxLineBytes
	}
	maxBytes := opts.MaxBytes
	if maxBytes <= 0 {
		maxBytes = int64(^uint64(0) >> 1)
	}
	return &CompressedLogReader{path: path, maxBytes: maxBytes, maxLineBytes: maxLine}
}

// InvalidLines counts lines skipped as not-an-object over all full reads.
func (r *CompressedLogReader) InvalidLines() int { return r.invalidLines }

// NoteInvalidLine is for a consumer whose own parse of a passed line failed.
func (r *CompressedLogReader) NoteInvalidLine() { r.invalidLines++ }

// Read implements LogReader.
func (r *CompressedLogReader) Read(onLine func([]byte), onReset func()) (ReadResult, error) {
	info, err := os.Stat(r.path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return ReadResult{Missing: true}, nil
		}
		return ReadResult{}, readFailure(err)
	}
	result := ReadResult{Size: info.Size(), Modified: info.ModTime()}
	stamp := fileStamp{info}
	if stamp.same(r.stamp) {
		result.Truncated = r.truncated
		return result, nil
	}
	// A bomb is not decompressed again on every poll: the same file fails the same way until it changes.
	if stamp.same(r.tooLargeStamp) {
		return ReadResult{}, ErrTooLarge
	}
	if r.stamp.info != nil {
		if onReset != nil {
			onReset()
		}
		result.DidReset = true
	}

	tail := newLineTail(r.maxBytes)
	invalid := 0
	oversized, err := ForEachLine(r.path, r.maxLineBytes, func(line []byte) error {
		first, last := trimmedEnds(line)
		if first < 0 {
			return nil
		}
		if line[first] != '{' || line[last] != '}' {
			invalid++
			return nil
		}
		tail.append(line)
		return nil
	})
	if err != nil {
		if errors.Is(err, ErrTooLarge) {
			r.tooLargeStamp = stamp
		}
		return ReadResult{}, err
	}
	tail.forEach(onLine)
	// A dropped line over the cap counts as truncated.
	dropped := tail.dropped || oversized > 0
	r.stamp = stamp
	r.truncated = dropped
	r.invalidLines += invalid
	r.peakStoredLines = tail.peakStored
	result.Lines = tail.count()
	result.InvalidLines = invalid
	result.OversizedLines = oversized
	result.Truncated = dropped
	return result, nil
}

// lineTail keeps the last lines of a stream, up to about maxBytes (never fewer than one line). Evicted lines are
// released at once and the slice is compacted, so memory follows maxBytes however many lines pass through.
type lineTail struct {
	maxBytes   int64
	storage    [][]byte
	head       int
	bytes      int64
	dropped    bool
	peakStored int // the most slots storage ever held, evicted ones included: what a test asserts to show memory stayed bounded
}

func newLineTail(maxBytes int64) *lineTail { return &lineTail{maxBytes: maxBytes} }

func (t *lineTail) count() int { return len(t.storage) - t.head }

// append stores a copy of line: the caller's slice is reused.
func (t *lineTail) append(line []byte) {
	t.storage = append(t.storage, bytes.Clone(line))
	t.bytes += int64(len(line))
	for t.bytes > t.maxBytes && t.count() > 1 {
		t.bytes -= int64(len(t.storage[t.head]))
		t.storage[t.head] = nil
		t.head++
		t.dropped = true
	}
	if t.head >= 1024 && t.head*2 >= len(t.storage) {
		n := copy(t.storage, t.storage[t.head:])
		clear(t.storage[n:])
		t.storage = t.storage[:n]
		t.head = 0
	}
	t.peakStored = max(t.peakStored, len(t.storage))
}

func (t *lineTail) forEach(body func([]byte)) {
	for _, line := range t.storage[t.head:] {
		body(line)
	}
}
