package limits

import (
	"go/parser"
	"go/token"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Swift: LimitsTests.swift. The tests read through limits.Read at a fixed instant and pick the CLI entry.

const testNow = 1_793_900_000.0

func claudeCache(fetchedAtMs, limits string) string {
	if fetchedAtMs == "" {
		fetchedAtMs = "1793500000250"
	}
	return `{"numStartups": 3, "cachedUsageUtilization": {"fetchedAtMs": ` + fetchedAtMs + `, "accountUuid": "synthetic",
  "utilization": {"five_hour": null, "seven_day": {"utilization": 8}, "limits": ` + limits + `}}}`
}

const twoWeekly = `[{"kind": "weekly_all", "group": "weekly", "percent": 8, "severity": "normal",
  "resets_at": "2026-11-06T16:00:00.803412+00:00", "scope": null, "is_active": true},
 {"kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
  "resets_at": "2026-11-06T15:59:59.803620+00:00",
  "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}]`

func entryFor(t *testing.T, h tempHome, cli CLI) Entry {
	t.Helper()
	for _, e := range h.read(testNow).Limits {
		if e.CLI == cli {
			return e
		}
	}
	t.Fatalf("no entry for %s", cli)
	return Entry{}
}

func wantMeasured(t *testing.T, e Entry) []Window {
	t.Helper()
	if e.State != Measured || e.At == nil {
		t.Fatalf("expected a reading, got %s", e.State)
	}
	return e.Windows
}

func ints(p *int) string {
	if p == nil {
		return "nil"
	}
	return strconv.Itoa(*p)
}

// Swift: LimitsTests.swift "Claude Code: each cached limit becomes a window with its share, reset and fetch time"
func TestClaudeCacheMeasured(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", claudeCache("", twoWeekly))
	e := entryFor(t, h, Claude)
	windows := wantMeasured(t, e)
	if *e.At != 1_793_500_000.25 {
		t.Errorf("at = %v", *e.At)
	}
	if e.Source == nil || *e.Source != ClaudeCache {
		t.Errorf("source = %v", e.Source)
	}
	if len(windows) != 2 {
		t.Fatalf("windows = %d", len(windows))
	}
	var ids, minutes, scopes []string
	for _, w := range windows {
		ids = append(ids, w.ID)
		minutes = append(minutes, ints(w.Minutes))
		if w.Scope == nil {
			scopes = append(scopes, "nil")
		} else {
			scopes = append(scopes, *w.Scope)
		}
	}
	if !slices.Equal(ids, []string{"weekly_all", "weekly_scoped:Fable"}) ||
		!slices.Equal(minutes, []string{"10080", "10080"}) || !slices.Equal(scopes, []string{"nil", "Fable"}) {
		t.Errorf("ids %v minutes %v scopes %v", ids, minutes, scopes)
	}
	if windows[0].UsedPercent != 8 || windows[1].UsedPercent != 0 || !windows[0].Active || windows[1].Active {
		t.Errorf("used/active: %+v", windows)
	}
	if windows[0].ResetsAt != 1_793_980_800.803 {
		t.Errorf("resetsAt = %v", windows[0].ResetsAt)
	}
}

// Swift: LimitsTests.swift "Claude Code: without CLAUDE_CONFIG_DIR the state file is the one in HOME"
func TestClaudeStateInHome(t *testing.T) {
	h := newTempHome(t)
	h.unsetClaude = true
	h.mkdir(".claude")
	h.write(".claude.json", claudeCache("", twoWeekly))
	wantMeasured(t, entryFor(t, h, Claude))
}

// Swift: LimitsTests.swift "Claude Code: no cache, an empty list, and no install read differently"
func TestClaudeNotRecorded(t *testing.T) {
	h := newTempHome(t)
	if s := entryFor(t, h, Claude).State; s != NotInstalled {
		t.Fatalf("no install: %s", s)
	}
	h.mkdir(".claude")
	if s := entryFor(t, h, Claude).State; s != NotRecorded {
		t.Fatalf("no state file: %s", s)
	}
	h.write(".claude/.claude.json", `{"numStartups": 3}`)
	if s := entryFor(t, h, Claude).State; s != NotRecorded {
		t.Fatalf("no cache key: %s", s)
	}
	h.write(".claude/.claude.json", claudeCache("", "[]"))
	if s := entryFor(t, h, Claude).State; s != NotRecorded {
		t.Fatalf("empty list: %s", s)
	}
}

// Swift: LimitsTests.swift "Claude Code: a broken file or an unknown entry shape is unreadable, never a partial list"
func TestClaudeUnreadable(t *testing.T) {
	oneBad := `[{"kind": "weekly_all", "group": "weekly", "percent": 8, "resets_at": "2026-11-06T16:00:00Z"},
 {"kind": "five_hour", "percent": "93%", "resets_at": "2026-11-03T20:00:00Z"}]`
	for name, text := range map[string]string{
		"broken json":      "{not json",
		"one bad entry":    claudeCache("", oneBad),
		"bad fetchedAtMs":  claudeCache(`"yesterday"`, twoWeekly),
		"bad reset":        claudeCache("", `[{"kind": "weekly_all", "percent": 8, "resets_at": "next week"}]`),
		"negative percent": claudeCache("", `[{"kind": "weekly_all", "percent": -1, "resets_at": "2026-11-06T16:00:00Z"}]`),
		"limits not array": claudeCache("", `{"kind": "weekly_all"}`),
		"invalid utf-8":    "{\"a\": \"\xff\"}",
	} {
		t.Run(name, func(t *testing.T) {
			h := newTempHome(t)
			h.write(".claude/.claude.json", text)
			e := entryFor(t, h, Claude)
			if e.State != Unreadable || len(e.Windows) != 0 {
				t.Fatalf("state %s windows %d", e.State, len(e.Windows))
			}
		})
	}
}

// Swift: LimitsTests.swift "Claude Code: window length comes from the group or kind, unknown names stay unknown"
func TestWindowMinutes(t *testing.T) {
	group := func(s string) *string { return &s }
	for _, c := range []struct {
		kind  string
		group *string
		want  string
	}{
		{"weekly_all", group("weekly"), "10080"},
		{"five_hour", nil, "300"},
		{"session", group("session"), "300"},
		{"monthly_all", group("monthly"), "nil"},
		{"seven_day_opus", nil, "10080"},
	} {
		if got := ints(windowMinutes(c.kind, c.group)); got != c.want {
			t.Errorf("%s: %s, want %s", c.kind, got, c.want)
		}
	}
}

func tokenCount(timestamp, rateLimits string) string {
	return `{"timestamp":"` + timestamp + `","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":` + rateLimits + `}}`
}

const weeklyLimits = `{"limit_id":"codex","limit_name":null,"primary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1794300000},"secondary":null,"credits":{"has_credits":false},"plan_type":"pro"}`

func (h tempHome) rollout(name string, lines []string, modified float64) {
	h.t.Helper()
	path := h.write(".codex/sessions/2026/11/03/"+name+".jsonl", strings.Join(lines, "\n")+"\n")
	setModified(h.t, path, modified)
}

// Swift: LimitsTests.swift "Codex: the newest token_count event with limits is the reading"
func TestCodexMeasured(t *testing.T) {
	h := newTempHome(t)
	older := `{"primary":{"used_percent":40.5,"window_minutes":300,"resets_at":1794200000},"secondary":{"used_percent":1,"window_minutes":10080,"resets_at":1794300000},"plan_type":"plus"}`
	h.rollout("rollout-a", []string{
		`{"timestamp":"2026-11-03T10:00:00.000Z","type":"session_meta","payload":{"id":"a"}}`,
		tokenCount("2026-11-03T10:01:00.000Z", older),
		tokenCount("2026-11-03T10:46:28.500Z", weeklyLimits),
		tokenCount("2026-11-03T10:47:00.000Z", "null"),
	}, testNow)
	e := entryFor(t, h, Codex)
	if e.Plan == nil || *e.Plan != "pro" {
		t.Errorf("plan = %v", e.Plan)
	}
	windows := wantMeasured(t, e)
	if *e.At != 1_793_702_788.5 {
		t.Errorf("at = %v", *e.At)
	}
	want := Window{ID: "primary", UsedPercent: 2, ResetsAt: 1_794_300_000, Active: true, Current: true}
	if len(windows) != 1 || windows[0].ID != want.ID || ints(windows[0].Minutes) != "10080" || windows[0].Scope != nil ||
		windows[0].UsedPercent != want.UsedPercent || windows[0].ResetsAt != want.ResetsAt || !windows[0].Active || !windows[0].Current {
		t.Errorf("windows = %+v", windows)
	}
}

// Swift: LimitsTests.swift "Codex: the most recently written log wins over the newest path"
func TestCodexNewestByModification(t *testing.T) {
	h := newTempHome(t)
	fresh := `{"primary":{"used_percent":70,"window_minutes":300,"resets_at":1794200000}}`
	h.rollout("rollout-z-new-path", []string{tokenCount("2026-11-03T09:00:00Z", weeklyLimits)}, testNow-3600)
	h.rollout("rollout-a-resumed", []string{tokenCount("2026-11-03T11:00:00Z", fresh)}, testNow)
	windows := wantMeasured(t, entryFor(t, h, Codex))
	if len(windows) != 1 || windows[0].UsedPercent != 70 {
		t.Errorf("windows = %+v", windows)
	}
}

// Swift: LimitsTests.swift "Codex: the older relative reset counts from the event time"
func TestCodexRelativeReset(t *testing.T) {
	h := newTempHome(t)
	relative := `{"primary":{"used_percent":12,"window_minutes":300,"resets_in_seconds":600}}`
	h.rollout("rollout-a", []string{tokenCount("2026-11-03T10:00:00Z", relative)}, testNow)
	e := entryFor(t, h, Codex)
	windows := wantMeasured(t, e)
	if windows[0].ResetsAt != *e.At+600 {
		t.Errorf("resetsAt %v, at %v", windows[0].ResetsAt, *e.At)
	}
}

// Swift: LimitsTests.swift "Codex: no install, no event and an unknown window shape read differently"
func TestCodexOtherStates(t *testing.T) {
	h := newTempHome(t)
	if s := entryFor(t, h, Codex).State; s != NotInstalled {
		t.Fatalf("no install: %s", s)
	}
	h.rollout("rollout-a", []string{`{"timestamp":"2026-11-03T10:00:00Z","type":"session_meta","payload":{}}`}, testNow)
	if s := entryFor(t, h, Codex).State; s != NotRecorded {
		t.Fatalf("no event: %s", s)
	}
	noReset := `{"primary":{"used_percent":12,"window_minutes":300}}`
	h.rollout("rollout-b", []string{tokenCount("2026-11-03T10:00:00Z", noReset)}, testNow)
	if s := entryFor(t, h, Codex).State; s != Unreadable {
		t.Fatalf("unknown window shape: %s", s)
	}
}

// Extra vectors: a rate_limits object with only unrelated members is not recorded but keeps the plan; a window
// length that is not a whole positive number stays unknown; a length past the Int range does not crash (Swift
// traps on Int(1e30), LimitsCodexLogs.swift:83).
func TestCodexWindowMinutesEdges(t *testing.T) {
	for name, c := range map[string]struct{ limits, minutes string }{
		"fractional":  {`{"primary":{"used_percent":1,"window_minutes":299.5,"resets_at":1794200000}}`, "nil"},
		"zero":        {`{"primary":{"used_percent":1,"window_minutes":0,"resets_at":1794200000}}`, "nil"},
		"huge":        {`{"primary":{"used_percent":1,"window_minutes":1e30,"resets_at":1794200000}}`, "nil"},
		"string":      {`{"primary":{"used_percent":1,"window_minutes":"300","resets_at":1794200000}}`, "nil"},
		"whole float": {`{"primary":{"used_percent":1,"window_minutes":300.0,"resets_at":1794200000}}`, "300"},
	} {
		t.Run(name, func(t *testing.T) {
			h := newTempHome(t)
			h.rollout("rollout-a", []string{tokenCount("2026-11-03T10:00:00Z", c.limits)}, testNow)
			if got := ints(wantMeasured(t, entryFor(t, h, Codex))[0].Minutes); got != c.minutes {
				t.Errorf("minutes %s, want %s", got, c.minutes)
			}
		})
	}
	h := newTempHome(t)
	h.rollout("rollout-a", []string{tokenCount("2026-11-03T10:00:00Z", `{"plan_type":"free"}`)}, testNow)
	e := entryFor(t, h, Codex)
	if e.State != NotRecorded || e.Plan == nil || *e.Plan != "free" {
		t.Errorf("state %s plan %v", e.State, e.Plan)
	}
}

// Swift: LimitsTests.swift "Gemini CLI keeps no limit on disk, so it is not measurable once installed"
func TestGemini(t *testing.T) {
	h := newTempHome(t)
	if s := entryFor(t, h, Gemini).State; s != NotInstalled {
		t.Fatalf("no install: %s", s)
	}
	h.mkdir(".gemini")
	if s := entryFor(t, h, Gemini).State; s != NotMeasurable {
		t.Fatalf("installed: %s", s)
	}
}

// Swift: LimitsTests.swift "read reports Claude Code, Codex and Gemini CLI in order"
func TestReadAllOrder(t *testing.T) {
	h := newTempHome(t)
	var order []CLI
	for _, e := range h.read(testNow).Limits {
		order = append(order, e.CLI)
		if e.Windows == nil {
			t.Errorf("%s: windows must be an empty slice, not nil", e.CLI)
		}
	}
	if !slices.Equal(order, []CLI{Claude, Codex, Gemini}) {
		t.Fatalf("order = %v", order)
	}
}

// Swift: LimitsTests.swift "a window whose reset has passed is no longer current"
func TestPassedResetIsNotCurrent(t *testing.T) {
	entry := Entry{Windows: []Window{{ResetsAt: 1000}}}
	if !entry.settled(999).Windows[0].Current {
		t.Error("before the reset the window is current")
	}
	if entry.settled(1000).Windows[0].Current {
		t.Error("at the reset the window is no longer current")
	}
}

// Swift: LimitsTests.swift "the Limits readers start no request and no process (S-R4, S-R5)". The Go form reads the
// imports of the package's own sources: nothing that opens a socket or starts a process.
func TestNoNetworkOrProcess(t *testing.T) {
	banned := []string{"net", "net/http", "net/rpc", "net/smtp", "net/textproto", "net/url", "os/exec", "os/signal", "syscall/js", "plugin", "unsafe"}
	files, err := filepath.Glob("*.go")
	if err != nil || len(files) == 0 {
		t.Fatalf("no sources: %v", err)
	}
	checked := 0
	for _, name := range files {
		if strings.HasSuffix(name, "_test.go") {
			continue
		}
		parsed, err := parser.ParseFile(token.NewFileSet(), name, nil, parser.ImportsOnly)
		if err != nil {
			t.Fatal(err)
		}
		checked++
		for _, spec := range parsed.Imports {
			path, _ := strconv.Unquote(spec.Path.Value)
			if slices.Contains(banned, path) || strings.HasPrefix(path, "net/") || strings.HasSuffix(path, "/proc") {
				t.Errorf("%s imports %s", name, path)
			}
		}
	}
	if checked < 5 {
		t.Fatalf("checked only %d sources", checked)
	}
}

// after5s is a timeout channel for the tests that must not block on a FIFO.
func after5s() <-chan time.Time { return time.After(5 * time.Second) }
