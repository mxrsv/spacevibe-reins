package logs

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"syscall"
	"time"
)

// ReadResult is what one Read found out about the file.
type ReadResult struct {
	// Missing: the file does not exist (yet, or any more).
	Missing  bool
	Size     int64
	Modified time.Time
	// Truncated: the first read started inside the file because of MaxBytes; earlier records were not read.
	Truncated bool
	// DidReset: the file was replaced or shrank, so reading restarted at the beginning and onReset was called.
	DidReset bool
	// Lines passed to onLine by this read.
	Lines int
	// InvalidLines were skipped because they do not look like a JSON object. Counted in total in InvalidLines().
	InvalidLines int
	// OversizedLines were skipped because they were longer than the cap.
	OversizedLines int
}

// LogReader reads the lines of a JSONL log that were added since the last read.
type LogReader interface {
	// Read calls onLine with each new complete, non-blank record line (valid only during the call). onReset, which may
	// be nil, is called first when the file was replaced or truncated and everything will be read again from the start.
	Read(onLine func([]byte), onReset func()) (ReadResult, error)
	// NoteInvalidLine is for a consumer whose own parse of a passed line failed; it adds to the same count.
	NoteInvalidLine()
}

// ReadError is a failed open, stat or read. It carries only errno, never file content or a path.
type ReadError struct{ Errno syscall.Errno }

func (e *ReadError) Error() string { return fmt.Sprintf("log cannot be read (errno %d)", int(e.Errno)) }

// readFailure turns an OS error into a ReadError; ErrNotRegular passes through.
func readFailure(err error) error {
	if errors.Is(err, ErrNotRegular) {
		return ErrNotRegular
	}
	var errno syscall.Errno
	if errors.As(err, &errno) {
		return &ReadError{Errno: errno}
	}
	return &ReadError{}
}

const (
	// TailChunkBytes is how much one pread-style step reads.
	TailChunkBytes = 256 * 1024
	// DefaultMaxLineBytes: longer lines are skipped.
	DefaultMaxLineBytes = 16 * 1024 * 1024
)

// TailOptions configure a TailReader. The zero value is the default.
type TailOptions struct {
	// MaxBytes: on the first read of a larger file, start this many bytes before the end (the first partial line is
	// dropped). 0 or less means the whole file.
	MaxBytes int64
	// MaxLineBytes: longer lines are skipped. 0 or less means DefaultMaxLineBytes.
	MaxLineBytes int
	// AnyLineShape passes every non-blank line, not only those that look like a JSON object.
	AnyLineShape bool
}

// TailReader is an incremental, read-only line reader for plain `.jsonl` logs. It remembers its byte offset, so a
// second Read returns only what was appended. The file's identity is device plus inode (os.SameFile): a log that is
// deleted and recreated is read again from the start, and so is one that shrank. A last line without its newline is
// held back until the newline arrives.
//
// Lines that do not start with `{` and end with `}` are not passed on: they are counted in InvalidLines. The check is
// a cheap shape test; a consumer whose own parse fails calls NoteInvalidLine to add to the same count.
// A TailReader is not safe for concurrent use.
type TailReader struct {
	path         string
	maxBytes     int64
	maxLineBytes int
	shapeCheck   bool

	offset         int64
	invalidLines   int
	oversizedLines int
	identity       os.FileInfo
	partial        []byte
	skipping       bool
	truncated      bool
	buffer         []byte
}

// NewTailReader returns a reader for path.
func NewTailReader(path string, opts TailOptions) *TailReader {
	maxLine := opts.MaxLineBytes
	if maxLine <= 0 {
		maxLine = DefaultMaxLineBytes
	}
	maxBytes := opts.MaxBytes
	if maxBytes <= 0 {
		maxBytes = int64(^uint64(0) >> 1)
	}
	return &TailReader{path: path, maxBytes: maxBytes, maxLineBytes: maxLine, shapeCheck: !opts.AnyLineShape}
}

// Path is the file this reader follows.
func (r *TailReader) Path() string { return r.path }

// Offset is how many bytes have been read.
func (r *TailReader) Offset() int64 { return r.offset }

// InvalidLines counts lines skipped as not-an-object since this reader was created (not reset by a file reset).
func (r *TailReader) InvalidLines() int { return r.invalidLines }

// OversizedLines counts lines skipped for length since this reader was created.
func (r *TailReader) OversizedLines() int { return r.oversizedLines }

// NoteInvalidLine is for a consumer whose own JSON parse of a passed line failed.
func (r *TailReader) NoteInvalidLine() { r.invalidLines++ }

func (r *TailReader) reset() {
	r.offset = 0
	r.identity = nil
	r.partial = r.partial[:0]
	r.skipping = false
	r.truncated = false
}

// Read implements LogReader.
func (r *TailReader) Read(onLine func([]byte), onReset func()) (ReadResult, error) {
	f, err := openRegular(r.path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return ReadResult{Missing: true}, nil
		}
		return ReadResult{}, readFailure(err)
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return ReadResult{}, readFailure(err)
	}

	var result ReadResult
	size := info.Size()
	if (r.identity != nil && !os.SameFile(r.identity, info)) || size < r.offset {
		r.reset()
		if onReset != nil {
			onReset()
		}
		result.DidReset = true
	}
	r.identity = info
	if r.offset == 0 && size > r.maxBytes {
		r.offset = size - r.maxBytes
		r.skipping = true
		r.truncated = true
	}

	invalidBefore, oversizedBefore := r.invalidLines, r.oversizedLines
	if r.buffer == nil {
		r.buffer = make([]byte, TailChunkBytes)
	}
	for r.offset < size {
		wanted := min(int64(TailChunkBytes), size-r.offset)
		n, err := f.ReadAt(r.buffer[:wanted], r.offset)
		if err != nil && !errors.Is(err, io.EOF) {
			return ReadResult{}, readFailure(err)
		}
		if n == 0 {
			break
		}
		r.offset += int64(n)
		r.consume(r.buffer[:n], onLine, &result.Lines)
	}
	result.Size = size
	result.Modified = info.ModTime()
	result.Truncated = r.truncated
	result.InvalidLines = r.invalidLines - invalidBefore
	result.OversizedLines = r.oversizedLines - oversizedBefore
	return result, nil
}

func (r *TailReader) consume(data []byte, onLine func([]byte), count *int) {
	start := 0
	for {
		i := bytes.IndexByte(data[start:], 0x0A)
		if i < 0 {
			break
		}
		newline := start + i
		switch {
		case r.skipping:
			r.skipping = false
			r.partial = r.partial[:0]
		case len(r.partial) == 0:
			r.emit(data[start:newline], onLine, count)
		default:
			r.partial = append(r.partial, data[start:newline]...)
			line := r.partial
			r.partial = r.partial[:0]
			r.emit(line, onLine, count)
		}
		start = newline + 1
	}
	if start >= len(data) || r.skipping {
		return
	}
	r.partial = append(r.partial, data[start:]...)
	if len(r.partial) > r.maxLineBytes {
		r.partial = r.partial[:0]
		r.skipping = true
		r.oversizedLines++
	}
}

func (r *TailReader) emit(line []byte, onLine func([]byte), count *int) {
	if len(line) > r.maxLineBytes {
		r.oversizedLines++
		return
	}
	first, last := trimmedEnds(line)
	if first < 0 {
		return // blank
	}
	if r.shapeCheck && (line[first] != '{' || line[last] != '}') {
		r.invalidLines++
		return
	}
	*count++
	onLine(line)
}

// isBlankByte is space, tab or carriage return (the Swift isBlank set; not `\n`, which splits lines).
func isBlankByte(b byte) bool { return b == ' ' || b == '\t' || b == '\r' }

// trimmedEnds returns the indexes of the first and last non-blank bytes, or -1, -1 for a blank line.
func trimmedEnds(line []byte) (first, last int) {
	first = -1
	for i, b := range line {
		if !isBlankByte(b) {
			first = i
			break
		}
	}
	if first < 0 {
		return -1, -1
	}
	for i := len(line) - 1; i >= first; i-- {
		if !isBlankByte(line[i]) {
			return first, i
		}
	}
	return first, first
}
