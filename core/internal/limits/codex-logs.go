package limits

import (
	"context"
	"math"
	"os"
	"slices"

	"spacevibe.dev/core/internal/logs"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// Codex writes its rate limits into every `token_count` event of a rollout (spec, Limits). The newest such event
// in the most recently written logs is the reading; its `primary` and `secondary` objects are the windows.

const (
	// codexTailBytes: only the end of a log is read, because the event repeats after every turn.
	codexTailBytes = 4 << 20
	// codexFilesTried: logs tried, newest first, before giving up. A brand-new session may not have logged a turn yet.
	codexFilesTried = 3
)

func readCodex(ctx context.Context, r roots.Roots) (Entry, error) {
	switch state := folderState(r.Codex.Root, NotRecorded); state {
	case NotInstalled, Unreadable:
		return Entry{CLI: Codex, State: state}, nil
	}
	failed := false
	for _, path := range newestLogs(r.Codex.Logs) {
		if err := ctx.Err(); err != nil {
			return Entry{}, err
		}
		line, outcome := lastEvent(path)
		switch outcome {
		case eventFailed:
			failed = true
		case eventLine:
			return codexReading(line), nil
		}
	}
	state := NotRecorded
	if failed {
		state = Unreadable
	}
	return Entry{CLI: Codex, State: state}, nil
}

// newestLogs lists logs by modification time, newest first: a resumed session appends to its old file in an
// older date folder.
func newestLogs(folder string) []string {
	type stamped struct {
		path string
		at   float64
	}
	var files []stamped
	for _, path := range logs.Walk(folder) {
		info, err := os.Stat(path)
		if err != nil {
			continue
		}
		t := info.ModTime()
		files = append(files, stamped{path, float64(t.Unix()) + float64(t.Nanosecond())/1e9})
	}
	slices.SortStableFunc(files, func(a, b stamped) int {
		switch {
		case a.at > b.at:
			return -1
		case a.at < b.at:
			return 1
		}
		return 0
	})
	paths := make([]string, 0, codexFilesTried)
	for _, f := range files[:min(len(files), codexFilesTried)] {
		paths = append(paths, f.path)
	}
	return paths
}

type eventOutcome int

const (
	eventNone eventOutcome = iota
	eventFailed
	eventLine
)

// lastEvent is the last `token_count` line whose `rate_limits` is an object (a null one is skipped) in the tail of
// the log. The log is opened through the logs package, which refuses a FIFO and reads at most codexTailBytes.
func lastEvent(path string) ([]byte, eventOutcome) {
	var last []byte
	_, err := logs.NewReader(path, codexTailBytes).Read(func(line []byte) {
		if textjs.Contains(line, `"type":"token_count"`) && textjs.Contains(line, `"rate_limits":{`) {
			last = append(last[:0], line...)
		}
	}, nil)
	switch {
	case err != nil:
		return nil, eventFailed
	case last == nil:
		return nil, eventNone
	}
	return last, eventLine
}

// codexReading reads `{ timestamp, payload: { rate_limits: { primary, secondary, plan_type } } }`. A window in a
// shape this code does not know makes the reading unreadable rather than showing the other window alone.
func codexReading(line []byte) Entry {
	unreadable := Entry{CLI: Codex, State: Unreadable}
	document, err := ojson.Parse(line)
	if err != nil {
		return unreadable
	}
	text, ok := memberString(document.Root(), "timestamp")
	if !ok {
		return unreadable
	}
	ms, ok := textjs.ParseTimestamp(text)
	if !ok {
		return unreadable
	}
	payload, ok := member(document.Root(), "payload")
	if !ok {
		return unreadable
	}
	limits, ok := member(payload, "rate_limits")
	if !ok {
		return unreadable
	}
	observed := dateSeconds(ms / 1000)
	var windows []Window
	for _, id := range []string{"primary", "secondary"} {
		raw, ok := member(limits, id)
		if !ok {
			continue
		}
		window, ok := codexWindow(id, raw, observed)
		if !ok {
			return unreadable
		}
		windows = append(windows, window)
	}
	var plan *string
	if p, ok := memberString(limits, "plan_type"); ok {
		plan = &p
	}
	if len(windows) == 0 {
		return Entry{CLI: Codex, State: NotRecorded, Plan: plan}
	}
	entry := measured(Codex, observed, windows)
	entry.Plan = plan
	return entry
}

// codexWindow reads `{ used_percent, window_minutes, resets_at }`, or the older `resets_in_seconds` counted from
// the event time.
func codexWindow(id string, raw ojson.Value, observed float64) (Window, bool) {
	used, ok := memberNumber(raw, "used_percent")
	if !ok || used < 0 {
		return Window{}, false
	}
	var resetsAt float64
	if seconds, ok := memberNumber(raw, "resets_at"); ok {
		resetsAt = dateSeconds(seconds)
	} else if relative, ok := memberNumber(raw, "resets_in_seconds"); ok {
		resetsAt = addingSeconds(observed, relative)
	} else {
		return Window{}, false
	}
	var minutes *int
	if m, ok := memberNumber(raw, "window_minutes"); ok && m > 0 && m == math.Round(m) && m < math.MaxInt64 {
		// Swift traps on Int(m) past the Int range; a length no CLI writes is read as unknown here instead.
		n := int(m)
		minutes = &n
	}
	return Window{ID: id, Minutes: minutes, UsedPercent: used, ResetsAt: resetsAt, Active: true}, true
}
