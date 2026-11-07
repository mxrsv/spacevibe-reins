// Package logs finds, opens and incrementally reads session logs, plain `.jsonl` and compressed `.jsonl.zst`.
//
// Ported from Sources/ReinsCore/ZstdStream.swift, LogFiles.swift (with LineSplitter) and TailReader.swift
// (TailReader, CompressedLogReader, LineTail). `modificationTime` is not ported: os.FileInfo.ModTime replaces it,
// and the plan's `fsx` package owns the stat helper for other callers.
//
// Lines handed to callbacks are slices into reused buffers: they are valid only until the callback returns.
// A callback that keeps a line must copy it. Errors never quote file content or paths (S-R3).
package logs

import (
	"errors"
	"io"
	"os"
	"sync"

	"github.com/klauspost/compress/zstd"
)

// Why a compressed log could not be read. Each is a fixed sentence; none carries file content.
var (
	// ErrCannotOpen: the file is missing, unreadable or not a regular file.
	ErrCannotOpen = errors.New("compressed log cannot be opened")
	// ErrCannotCreateDecoder: the zstd decoder could not be set up.
	ErrCannotCreateDecoder = errors.New("zstd decoder cannot be created")
	// ErrCorrupt: the bytes are not a valid zstd stream.
	ErrCorrupt = errors.New("compressed log is corrupt")
	// ErrTruncated: the file ends inside a frame.
	ErrTruncated = errors.New("compressed log is truncated")
	// ErrTooLarge: the stream decompressed past its output cap (a tiny file that expands to gigabytes), or declares
	// a window beyond the memory cap. Callers treat the log as unreadable.
	ErrTooLarge = errors.New("compressed log expands past the size cap")
)

const (
	// DefaultMaxOutputBytes is far above any real session log (the largest on a heavy machine is tens of MB) and far
	// below a decompression bomb.
	DefaultMaxOutputBytes = 512 << 20
	// zstdMemoryCap bounds the decoder's window and memory, the same size as the output cap.
	zstdMemoryCap = 512 << 20
	// zstdChunkBytes is the size of one decoded chunk (libzstd's ZSTD_DStreamOutSize).
	zstdChunkBytes = 128 << 10
	// maxEmptyReads stops a decoder that keeps returning nothing without an error.
	maxEmptyReads = 100
)

// ZstdStream reads a `.zst` file as a sequence of decompressed chunks (concatenated frames are one stream).
// Memory stays at the decoder's buffers whatever the file size. The total decompressed size is capped, so a small
// file cannot keep a reader busy for gigabytes; past the cap NextChunk returns ErrTooLarge. There is no wall-clock
// budget: the cap bounds the work.
type ZstdStream struct {
	maxOutput int64
	total     int64
	decoder   *zstd.Decoder
	source    *recordingReader
	file      *os.File
	buf       []byte
	pending   error // an error that came with the last bytes; returned by the next call
	err       error // sticky
}

// OpenZstdStream opens path. maxOutputBytes <= 0 means DefaultMaxOutputBytes.
// Any open failure, including a FIFO or a directory, is ErrCannotOpen.
func OpenZstdStream(path string, maxOutputBytes int64) (*ZstdStream, error) {
	f, err := openRegular(path)
	if err != nil {
		return nil, ErrCannotOpen
	}
	s, err := newZstdStream(f, maxOutputBytes)
	if err != nil {
		_ = f.Close()
		return nil, err
	}
	s.file = f
	return s, nil
}

// newZstdStream is the seam tests use to feed a source that fails the way a disk read can.
func newZstdStream(r io.Reader, maxOutputBytes int64) (*ZstdStream, error) {
	if maxOutputBytes <= 0 {
		maxOutputBytes = DefaultMaxOutputBytes
	}
	source := &recordingReader{r: r}
	decoder, err := zstd.NewReader(source,
		zstd.WithDecoderConcurrency(1), // synchronous decode: no goroutines, reads happen inside Read
		zstd.WithDecoderMaxMemory(zstdMemoryCap),
		zstd.WithDecoderMaxWindow(zstdMemoryCap),
	)
	if err != nil {
		if source.failure() != nil {
			return nil, source.failure()
		}
		return nil, ErrCannotCreateDecoder
	}
	return &ZstdStream{maxOutput: maxOutputBytes, decoder: decoder, source: source, buf: make([]byte, zstdChunkBytes)}, nil
}

// Close releases the decoder and the file. It is safe to call twice.
func (s *ZstdStream) Close() error {
	if s.decoder != nil {
		s.decoder.Close()
		s.decoder = nil
	}
	if s.file != nil {
		err := s.file.Close()
		s.file = nil
		return err
	}
	return nil
}

// NextChunk returns the next decompressed bytes, or io.EOF at the end of the file. The slice is reused by the next
// call. Errors are ErrCorrupt, ErrTruncated, ErrTooLarge, or the I/O error of the source, returned as it came.
func (s *ZstdStream) NextChunk() ([]byte, error) {
	if s.err != nil {
		return nil, s.err
	}
	if s.pending != nil {
		return nil, s.fail(s.pending)
	}
	for empty := 0; empty < maxEmptyReads; empty++ {
		n, err := s.decoder.Read(s.buf)
		if n > 0 {
			s.total += int64(n)
			if s.total > s.maxOutput {
				return nil, s.fail(ErrTooLarge)
			}
			if err != nil {
				s.pending = err
			}
			return s.buf[:n], nil
		}
		if err != nil {
			return nil, s.fail(err)
		}
	}
	return nil, s.fail(ErrCorrupt)
}

// fail classifies err once and makes it sticky. io.EOF stays io.EOF.
func (s *ZstdStream) fail(err error) error {
	s.err = s.classify(err)
	return s.err
}

// classify maps the decoder's outcomes onto this package's. An error the source returned is I/O, not a format
// problem, and is returned unchanged: reading it as end of file would report a half-read log as complete.
func (s *ZstdStream) classify(err error) error {
	switch {
	case errors.Is(err, io.EOF):
		return io.EOF
	case errors.Is(err, ErrTooLarge), errors.Is(err, ErrCorrupt):
		return err
	}
	if failure := s.source.failure(); failure != nil {
		return failure
	}
	switch {
	case errors.Is(err, io.ErrUnexpectedEOF):
		return ErrTruncated
	case errors.Is(err, zstd.ErrWindowSizeExceeded), errors.Is(err, zstd.ErrDecoderSizeExceeded), errors.Is(err, zstd.ErrFrameSizeExceeded):
		return ErrTooLarge
	}
	return ErrCorrupt
}

// ForEachChunk calls body for every decompressed chunk and stops at the first body error. The stream is not closed.
func (s *ZstdStream) ForEachChunk(body func([]byte) error) error {
	for {
		chunk, err := s.NextChunk()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		if err := body(chunk); err != nil {
			return err
		}
	}
}

// ReadAllZstd returns the whole decompressed file in memory. For tests and small files; use ForEachChunk for logs.
func ReadAllZstd(path string) ([]byte, error) {
	s, err := OpenZstdStream(path, 0)
	if err != nil {
		return nil, err
	}
	defer s.Close()
	var out []byte
	err = s.ForEachChunk(func(chunk []byte) error {
		out = append(out, chunk...)
		return nil
	})
	return out, err
}

// recordingReader remembers the first non-EOF error its source returned, so the decoder's own wording of that error
// (or a format error it raised after it) is never mistaken for a corrupt file.
type recordingReader struct {
	r   io.Reader
	mu  sync.Mutex
	err error
}

func (r *recordingReader) Read(p []byte) (int, error) {
	n, err := r.r.Read(p)
	if err != nil && err != io.EOF {
		r.mu.Lock()
		if r.err == nil {
			r.err = err
		}
		r.mu.Unlock()
	}
	return n, err
}

func (r *recordingReader) failure() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.err
}
