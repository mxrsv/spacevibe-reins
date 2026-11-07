package limits

import (
	"strings"

	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
)

// Claude Code's own usage cache, `cachedUsageUtilization` in its global state file (spec, Limits). The format is
// undocumented and Claude Code refreshes it only when it fetches usage itself, so the reading carries its fetch
// time. Only `fetchedAtMs` and `utilization.limits[]` are read; the file also holds account data, which is never
// kept. One entry in a shape this code does not know makes the whole reading unreadable: a partial list could
// hide the window that is nearly used up.

const (
	// maxCacheBytes: a state file past this is not parsed. The owner's is about 0.4 MB.
	maxCacheBytes  = 64 << 20
	weekMinutes    = 7 * 24 * 60
	sessionMinutes = 5 * 60
)

func readClaudeCache(r roots.Roots) Entry {
	switch fsx.PathPresence(r.ClaudeState) {
	case fsx.Missing:
		return Entry{CLI: Claude, State: folderState(r.Claude.Root, NotRecorded)}
	case fsx.Unknown:
		return Entry{CLI: Claude, State: Unreadable}
	}
	data, err := fsx.ReadRegular(r.ClaudeState, maxCacheBytes)
	if err != nil {
		return Entry{CLI: Claude, State: Unreadable}
	}
	document, err := ojson.Parse(data)
	if err != nil {
		return Entry{CLI: Claude, State: Unreadable}
	}
	cache, ok := member(document.Root(), "cachedUsageUtilization")
	if !ok {
		return Entry{CLI: Claude, State: NotRecorded}
	}
	// Every outcome of a present cache names it as the source, an unreadable one included.
	entry := cacheState(cache)
	source := ClaudeCache
	entry.Source = &source
	return entry
}

func cacheState(cache ojson.Value) Entry {
	fail := func(state State) Entry { return Entry{CLI: Claude, State: state} }
	fetchedMs, ok := memberNumber(cache, "fetchedAtMs")
	if !ok {
		return fail(Unreadable)
	}
	utilization, ok := member(cache, "utilization")
	if !ok {
		return fail(Unreadable)
	}
	list, ok := member(utilization, "limits")
	if !ok {
		return fail(Unreadable)
	}
	entries, ok := list.ArrayValue()
	if !ok {
		return fail(Unreadable)
	}
	windows := make([]Window, 0, len(entries))
	for _, entry := range entries {
		window, ok := cacheWindow(entry)
		if !ok {
			return fail(Unreadable)
		}
		windows = append(windows, window)
	}
	if len(windows) == 0 {
		return fail(NotRecorded)
	}
	return measured(Claude, dateSeconds(fetchedMs/1000), windows)
}

// cacheWindow reads `{ kind, group, percent, resets_at, scope: { model: { display_name } }, is_active }`.
func cacheWindow(entry ojson.Value) (Window, bool) {
	kind, ok := memberString(entry, "kind")
	if !ok {
		return Window{}, false
	}
	percent, ok := memberNumber(entry, "percent")
	if !ok || percent < 0 {
		return Window{}, false
	}
	resetText, ok := memberString(entry, "resets_at")
	if !ok {
		return Window{}, false
	}
	resetMs, ok := textjs.ParseTimestamp(resetText)
	if !ok {
		return Window{}, false
	}
	var group *string
	if g, ok := memberString(entry, "group"); ok {
		group = &g
	}
	var scope *string
	if s, ok := scopeName(entry); ok {
		scope = &s
	}
	id := kind
	if scope != nil {
		id = kind + ":" + *scope
	}
	active := true
	if v, ok := member(entry, "is_active"); ok {
		if b, isBool := v.BoolValue(); isBool {
			active = b
		}
	}
	return Window{
		ID: id, Minutes: windowMinutes(kind, group), Scope: scope, UsedPercent: percent,
		ResetsAt: dateSeconds(resetMs / 1000), Active: active,
	}, true
}

func scopeName(entry ojson.Value) (string, bool) {
	scope, ok := member(entry, "scope")
	if !ok {
		return "", false
	}
	model, ok := member(scope, "model")
	if !ok {
		return "", false
	}
	return memberString(model, "display_name")
}

// windowMinutes: seen on the owner's Mac, `weekly_all` and `weekly_scoped` in group `weekly`. The five-hour names
// are the ones the cache's own top-level keys use; any other name leaves the length unknown rather than guessed.
func windowMinutes(kind string, group *string) *int {
	inGroup := func(name string) bool { return group != nil && *group == name }
	switch {
	case inGroup("weekly") || strings.HasPrefix(kind, "weekly") || strings.HasPrefix(kind, "seven_day"):
		m := weekMinutes
		return &m
	case inGroup("session") || strings.HasPrefix(kind, "session") || strings.HasPrefix(kind, "five_hour"):
		m := sessionMinutes
		return &m
	}
	return nil
}
