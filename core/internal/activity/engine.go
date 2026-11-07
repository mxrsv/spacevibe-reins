package activity

import (
	"context"
	"sort"
	"sync"
	"time"

	"spacevibe.dev/core/internal/logs"
	"spacevibe.dev/core/internal/pricing"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

const (
	maxSubagentLogs = 50
	dayMs           = 86_400_000.0
	noCostEstimate  = "The log is too large to read in full, so no estimate."
	noTranscript    = "No transcript found for this session."
)

type cacheEntry struct {
	reader    logs.LogReader
	state     *logState
	truncated bool
}

// Engine reads session logs incrementally. It keeps the read offset and folded state of every log between calls,
// so a repeated Read reads only the bytes appended since (a compressed rollout is read again only when its file
// changes). Reads never overlap: the mutex stands in for the Swift actor.
type Engine struct {
	mu    sync.Mutex
	cache map[string]*cacheEntry
}

// NewEngine returns an engine with an empty cache.
func NewEngine() *Engine { return &Engine{cache: map[string]*cacheEntry{}} }

// advance folds what was appended to a log since the last read. It returns nil for a log that is missing or that
// cannot be read; an unreadable log stays out of the lists but keeps its cache entry, as in Swift.
func (e *Engine) advance(f logFile, maxBytes int64) *cacheEntry {
	entry, ok := e.cache[f.path]
	if !ok {
		var reader logs.LogReader
		if logs.IsCompressed(f.path) {
			reader = logs.NewCompressedLogReader(f.path, logs.CompressedOptions{MaxBytes: maxBytes})
		} else {
			reader = logs.NewTailReader(f.path, logs.TailOptions{MaxBytes: maxBytes, AnyLineShape: true})
		}
		entry = &cacheEntry{reader: reader, state: newLogState(f.cli)}
		e.cache[f.path] = entry
	}
	result, err := entry.reader.Read(
		func(line []byte) { fold(entry.state, line) },
		func() { entry.state = newLogState(f.cli) },
	)
	if err != nil {
		return nil
	}
	if result.Missing {
		delete(e.cache, f.path)
		return nil
	}
	entry.truncated = result.Truncated
	return entry
}

type foldedLog struct {
	file  logFile
	entry *cacheEntry
}

// readContext is what the session builders read from one Read call.
type readContext struct {
	roots        roots.Roots
	nowMs        float64
	opts         Options
	proc         proc.Adapter
	memo         projectMemo
	index        logIndex
	foldedByPath map[string]*cacheEntry
	codexPids    map[int]bool
}

// Read builds the report: roots are where the logs live, now is the clock every age is computed against, and
// adapter is the process view (tests pass a fake). It returns ctx.Err() when cancelled; the engine's cache stays
// valid, so the next Read goes on from the folded offsets.
func (e *Engine) Read(ctx context.Context, r roots.Roots, now time.Time, adapter proc.Adapter, opts Options) (Report, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if err := ctx.Err(); err != nil {
		return Report{}, err
	}
	nowMs := float64(now.UnixNano()) / 1e6
	index := listLogs(r)
	memo := projectMemo{}

	// 1. Live processes.
	claudeLive, threads := liveProcesses(ctx, r, index, adapter)
	codexPids := map[int]bool{}
	for _, t := range threads {
		if t.ThreadID != "" {
			codexPids[t.Pid] = true
		}
	}

	// 2. Which logs to fold: live ones in full, the rest only if recent.
	live := map[string]bool{}
	for _, c := range claudeLive {
		if c.main != nil {
			live[c.main.path] = true
		}
		for _, f := range c.subs[:min(len(c.subs), maxSubagentLogs)] {
			live[f.path] = true
		}
	}
	for _, t := range threads {
		if f, ok := index.codexByID[t.ThreadID]; ok && t.ThreadID != "" {
			live[f.path] = true
		}
	}
	cutoff := nowMs - float64(opts.HistoryDays)*dayMs
	var recent []logFile
	for _, f := range index.files {
		if f.mtimeMs >= cutoff && !live[f.path] {
			recent = append(recent, f)
		}
	}
	sort.SliceStable(recent, func(i, j int) bool { return recent[i].mtimeMs > recent[j].mtimeMs })
	if len(recent) > opts.MaxHistoryFiles {
		recent = recent[:opts.MaxHistoryFiles]
	}
	var targets []logFile
	for _, f := range index.files {
		if live[f.path] {
			targets = append(targets, f)
		}
	}
	targets = append(targets, recent...)
	var folded []foldedLog
	foldedByPath := map[string]*cacheEntry{}
	for _, f := range targets {
		if err := ctx.Err(); err != nil {
			return Report{}, err
		}
		maxBytes := opts.HistoryTailBytes
		if live[f.path] {
			maxBytes = opts.LiveTailBytes
		}
		if entry := e.advance(f, maxBytes); entry != nil {
			folded = append(folded, foldedLog{f, entry})
			foldedByPath[f.path] = entry
		}
	}
	wanted := map[string]bool{}
	for _, f := range targets {
		wanted[f.path] = true
	}
	for path := range e.cache {
		if !wanted[path] {
			delete(e.cache, path)
		}
	}

	// 3. Sessions.
	rc := &readContext{roots: r, nowMs: nowMs, opts: opts, proc: adapter, memo: memo, index: index, foldedByPath: foldedByPath, codexPids: codexPids}
	sessions := append(claudeSessions(claudeLive, rc), codexSessions(ctx, threads, rc)...)
	sort.SliceStable(sessions, func(i, j int) bool {
		a, b := sessions[i], sessions[j]
		if a.CLI != b.CLI {
			return a.CLI < b.CLI
		}
		return agoKey(a.LastWriteAgoMs) < agoKey(b.LastWriteAgoMs)
	})

	// 4. Cross-session lists.
	sessionByPath := map[string]string{}
	for _, f := range index.files {
		if _, seen := sessionByPath[f.path]; !seen {
			sessionByPath[f.path] = f.session
		}
	}
	entries := make([]logEntry, 0, len(folded))
	truncated := 0
	for _, item := range folded {
		st := item.entry.state
		name, ok := sessionByPath[item.file.path]
		if !ok {
			name = item.file.path
		}
		project, hasProject := projectName(st.cwd, st.worktreeOriginal, memo)
		entries = append(entries, logEntry{state: st, session: string(st.cli) + ":" + name, project: project, hasProject: hasProject})
		if item.entry.truncated {
			truncated++
		}
	}
	if err := ctx.Err(); err != nil {
		return Report{}, err
	}
	limits := make([]Limit, len(limitCodes))
	for i, l := range limitCodes {
		limits[i] = Limit{CLI: l.cli, Code: l.code, Text: l.code.Text()}
	}
	return Report{
		Sessions: nonNil(sessions), Failures: nonNil(groupFailures(entries, opts.FailureLimit)), Files: nonNil(groupFiles(entries, opts.FileLimit)),
		Unmeasurable: limits, Stats: Stats{Logs: len(folded), Truncated: truncated},
	}, nil
}

func nonNil[T any](s []T) []T {
	if s == nil {
		return []T{}
	}
	return s
}

// agoKey sorts a missing "last write" after every number.
func agoKey(v *float64) float64 {
	if v == nil {
		return inf
	}
	return *v
}

// costFor sums the usage of the logs of one session and prices it; a truncated log gives no estimate.
func costFor(entries []*cacheEntry) (*Cost, *string) {
	for _, e := range entries {
		if e.truncated {
			return nil, strPtr(noCostEstimate)
		}
	}
	var merged textjs.OrderedMap[usage]
	for _, e := range entries {
		for _, m := range e.state.metrics.Entries() {
			o, _ := merged.Get(m.Key)
			o.Input += m.Value.Input
			o.Output += m.Value.Output
			o.CacheWrite += m.Value.CacheWrite
			o.CacheWriteLong += m.Value.CacheWriteLong
			o.CacheRead += m.Value.CacheRead
			merged.Set(m.Key, o)
		}
	}
	var list []pricing.ModelUsage
	for _, m := range merged.Entries() {
		list = append(list, pricing.ModelUsage{Model: m.Key, Usage: m.Value})
	}
	estimate := pricing.EstimateCost(list, pricing.Models())
	if estimate.HasUSD {
		return &Cost{USD: estimate.USD, Estimated: true}, nil
	}
	return nil, strPtr(estimate.Note)
}
