package logs

import (
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Finding and opening session logs. Older Codex rollouts sit on disk as `.jsonl.zst`, so a reader that only knows
// `.jsonl` silently loses most of a machine's Codex history.

const (
	plainReadChunk    = 1 << 20
	plainMinReadChunk = 4 << 10
)

// logSuffixes in match order: the longest first.
var logSuffixes = []string{".jsonl.zstd", ".jsonl.zst", ".jsonl"}

// IsLog reports whether name is `x.jsonl`, `x.jsonl.zst` or `x.jsonl.zstd`.
func IsLog(name string) bool {
	_, ok := stripLogSuffix(name)
	return ok
}

// IsCompressed reports whether the file name ends in `.zst` or `.zstd`.
func IsCompressed(path string) bool {
	name := filepath.Base(path)
	return strings.HasSuffix(name, ".zst") || strings.HasSuffix(name, ".zstd")
}

// BaseName is the file name without `.jsonl` or `.jsonl.zst`, so both forms of one session share a name.
func BaseName(path string) string {
	name := filepath.Base(path)
	if base, ok := stripLogSuffix(name); ok {
		return base
	}
	return name
}

func stripLogSuffix(name string) (string, bool) {
	for _, suffix := range logSuffixes {
		if strings.HasSuffix(name, suffix) {
			return strings.TrimSuffix(name, suffix), true
		}
	}
	return "", false
}

// Walk lists every log under directory, sorted by path (byte order). When a session exists in both forms in one
// folder, only the plain `.jsonl` is listed: it is the one still written. Symlinks are not followed. A folder that
// cannot be read counts as empty. Entries are joined onto directory as given, never symlink-resolved: callers count
// the path components of the root they passed.
func Walk(directory string) []string {
	var out []string
	collect(directory, &out)
	sort.Strings(out)
	return out
}

func collect(directory string, out *[]string) {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return
	}
	present := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		present[entry.Name()] = struct{}{}
	}
	for _, entry := range entries {
		name := entry.Name()
		path := filepath.Join(directory, name)
		switch {
		case entry.IsDir():
			collect(path, out)
		case entry.Type().IsRegular():
			base, ok := stripLogSuffix(name)
			if !ok {
				continue
			}
			if _, plain := present[base+".jsonl"]; IsCompressed(path) && plain {
				continue
			}
			*out = append(*out, path)
		}
	}
}

// ForEachChunk calls body with the log's bytes in chunks, decompressing `.zst`. The slice is reused between calls.
// Errors: the ZstdStream errors, ErrNotRegular, or a file error.
func ForEachChunk(path string, body func([]byte) error) error {
	if IsCompressed(path) {
		s, err := OpenZstdStream(path, 0)
		if err != nil {
			return err
		}
		defer s.Close()
		return s.ForEachChunk(body)
	}
	f, err := openRegular(path)
	if err != nil {
		return readFailure(err)
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return readFailure(err)
	}
	// Small logs need no full-size buffer. Keep a floor for files that grow while read;
	// their initial size is a hint, never a limit on how many bytes we consume.
	bufferSize := min(int64(plainReadChunk), max(info.Size(), int64(plainMinReadChunk)))
	buf := make([]byte, int(bufferSize))
	for {
		n, err := f.Read(buf)
		if n > 0 {
			if berr := body(buf[:n]); berr != nil {
				return berr
			}
		}
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return readFailure(err)
		}
	}
}

// ForEachLine calls body with each line of the log, without its `\n` (a trailing `\r` is kept). Empty lines are passed
// too; a last line without a newline is passed. Lines longer than maxLineBytes are skipped and counted in the result
// (maxLineBytes <= 0 means no limit). The slice is valid only during the call.
func ForEachLine(path string, maxLineBytes int, body func([]byte) error) (oversized int, err error) {
	splitter := lineSplitter{maxLineBytes: maxLineBytes}
	err = ForEachChunk(path, func(chunk []byte) error { return splitter.feed(chunk, body) })
	if err != nil {
		return splitter.oversized, err
	}
	err = splitter.finish(body)
	return splitter.oversized, err
}

// NewReader picks the reader for the log: TailReader for plain files, CompressedLogReader for `.zst`.
// maxBytes <= 0 means no limit.
func NewReader(path string, maxBytes int64) LogReader {
	if IsCompressed(path) {
		return NewCompressedLogReader(path, CompressedOptions{MaxBytes: maxBytes})
	}
	return NewTailReader(path, TailOptions{MaxBytes: maxBytes})
}
