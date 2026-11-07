package usage

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/logs"
	"spacevibe.dev/core/internal/roots"
)

const (
	// ScanVersion is bumped when the parser changes what a log file yields, so cached results are rescanned.
	// Same number as Node usage and the Swift engine.
	ScanVersion = 2
	// DefaultMaxLineBytes: lines longer than this are skipped, not parsed.
	DefaultMaxLineBytes = 32 << 20
	// ProgressEvery: the progress callback runs after this many files, and once at the end.
	ProgressEvery = 20
	// cancelCheckLines is how many lines of one log are read between looks at the context.
	cancelCheckLines = 4096
)

// Scanner scans the logs under a set of roots and remembers the last finished result of the process.
type Scanner struct {
	roots roots.Roots
	// MaxLineBytes caps one line; 0 means DefaultMaxLineBytes.
	MaxLineBytes int

	mu      sync.Mutex
	running bool
	last    *Result
}

// NewScanner returns a scanner for the logs and data folder of r.
func NewScanner(r roots.Roots) *Scanner { return &Scanner{roots: r} }

// Last is the result of the last scan that finished in this process, if any. loadout.rows attaches it.
func (s *Scanner) Last() (Result, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.last == nil {
		return Result{}, false
	}
	return *s.last, true
}

// Scan is the usage.scan method: it scans every log, stores the result as the process's usage state and
// returns it. A second Scan while one runs is refused with status 409. progress, which may be nil, is called
// after every ProgressEvery files and once at the end, from the calling goroutine. The only error besides
// the 409 is the context's: a cancelled scan leaves the cache as it was and the stored state unchanged.
func (s *Scanner) Scan(ctx context.Context, progress func(Progress)) (Result, error) {
	s.mu.Lock()
	if s.running {
		s.mu.Unlock()
		return Result{}, coreerr.NewStatus("A usage scan is already running.", coreerr.StatusConflict)
	}
	s.running = true
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		s.running = false
		s.mu.Unlock()
	}()
	result, err := s.scan(ctx, progress)
	if err != nil {
		return Result{}, err
	}
	s.mu.Lock()
	s.last = &result
	s.mu.Unlock()
	return result, nil
}

type target struct {
	path string
	cli  CLI
}

func (s *Scanner) scan(ctx context.Context, progress func(Progress)) (Result, error) {
	maxLine := s.MaxLineBytes
	if maxLine <= 0 {
		maxLine = DefaultMaxLineBytes
	}
	cache := loadCache(s.roots.Data)
	var targets []target
	for _, p := range logs.Walk(s.roots.Claude.Logs) {
		targets = append(targets, target{p, Claude})
	}
	for _, p := range logs.Walk(s.roots.Codex.Logs) {
		targets = append(targets, target{p, Codex})
	}
	next := make(map[string]cachedFile, len(targets))
	for index, t := range targets {
		if err := ctx.Err(); err != nil {
			return Result{}, err
		}
		entry, ok, err := s.entry(ctx, t, cache[t.path], maxLine)
		if err != nil {
			return Result{}, err
		}
		if ok {
			next[t.path] = entry
		}
		if done := index + 1; done%ProgressEvery == 0 && progress != nil {
			progress(Progress{Done: done, Total: len(targets)})
		}
	}
	if progress != nil {
		progress(Progress{Done: len(targets), Total: len(targets)})
	}
	// Deliberate difference: Swift saves a cache even when the context ended after the last file.
	if err := ctx.Err(); err != nil {
		return Result{}, err
	}
	saveCache(next, s.roots.Data)
	return aggregate(next, len(targets)), nil
}

// entry is the cached record when the log is unchanged, otherwise a fresh parse. ok is false when the log
// cannot be statted or read to the end; err is only ever the context's.
func (s *Scanner) entry(ctx context.Context, t target, cached cachedFile, maxLine int) (entry cachedFile, ok bool, err error) {
	info, statErr := os.Stat(t.path)
	if statErr != nil {
		return cachedFile{}, false, nil
	}
	mtimeMs := info.ModTime().UnixMilli()
	stamp := strconv.FormatInt(info.Size(), 10) + ":" + strconv.FormatInt(mtimeMs, 10)
	if cached.Stamp == stamp && cached.V == ScanVersion {
		return cached, true, nil
	}
	return scanFile(ctx, t, stamp, isoDay(mtimeMs), maxLine)
}

// scanFile parses one log. ok is false when the file cannot be read to the end (missing, a broken zstd
// frame, a FIFO); err is only ever the context's.
func scanFile(ctx context.Context, t target, stamp, fallbackDay string, maxLine int) (cachedFile, bool, error) {
	rec := newFileRecord()
	var first *string
	lines := 0
	_, readErr := logs.ForEachLine(t.path, maxLine, func(line []byte) error {
		if lines++; lines%cancelCheckLines == 0 {
			if err := ctx.Err(); err != nil {
				return err
			}
		}
		if first == nil {
			if d, found := dayOf(line); found {
				first = &d
			}
		}
		if t.cli == Claude {
			claudeLine(line, &rec, fallbackDay)
		} else {
			codexLine(line, &rec, fallbackDay)
		}
		return nil
	})
	if readErr != nil {
		return cachedFile{}, false, ctx.Err()
	}
	return cachedFile{V: ScanVersion, Stamp: stamp, CLI: t.cli, Session: sessionID(t.path), First: first, Rec: rec}, true, nil
}

// sessionID: a subagent log belongs to the session of the folder that holds subagents/; any other log is its
// own session.
func sessionID(path string) string {
	parts := strings.Split(filepath.ToSlash(path), "/")
	for i := len(parts) - 1; i > 0; i-- {
		if parts[i] == "subagents" {
			return parts[i-1]
		}
	}
	return logs.BaseName(path)
}
