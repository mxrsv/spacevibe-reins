package limits

import (
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/ojson"
)

// Swift: LimitsStatuslineTests.swift, read side. The Swift tests produce their snapshots by running the collector
// (capture); the collector is G2.6, so these tests write the files it leaves by hand, the same way the golden
// cases do (LimitsGoldenTests "the status line snapshot the cases write by hand is what the collector writes").
// The capture and install tests (invalidInput, managedDirectories' writes, setup) belong to G2.6.

const (
	reset      = 1_794_000_000
	statusNow  = 1_793_900_000.0
	defaultAcc = "synthetic-account"
)

func accountState(name string) string {
	return `{"oauthAccount":{"accountUuid":"` + name + `","organizationUuid":"synthetic-org"},
 "cachedUsageUtilization":{"fetchedAtMs":1793800000000,"utilization":{"limits":[
 {"kind":"weekly_all","group":"weekly","percent":62,"resets_at":"2026-11-06T16:00:00Z"}]}}}`
}

type snapWindow struct {
	key   string
	used  string
	reset int
}

// snapshot writes the file the collector leaves for one session, with the modification time of its observation.
func (h tempHome) snapshot(session, account string, observed float64, windows ...snapWindow) string {
	h.t.Helper()
	var members []string
	for _, w := range windows {
		members = append(members, fmt.Sprintf(`"%s":{"used_percentage":%s,"resets_at":%d}`, w.key, w.used, w.reset))
	}
	text := fmt.Sprintf(`{"account":"%s","observedAt":%v,"rate_limits":{%s}}`,
		h.accountKeyFor(account, "synthetic-org"), observed, strings.Join(members, ","))
	path := h.write(".spacevibe/claude-limits/"+session+".json", text)
	setModified(h.t, path, observed)
	return path
}

func (h tempHome) weekly(session, used string, observed float64) {
	h.t.Helper()
	h.snapshot(session, defaultAcc, observed, snapWindow{"seven_day", used, reset})
}

func (h tempHome) claude(now float64) Entry {
	h.t.Helper()
	return h.read(now).Limits[0]
}

func usedPercents(windows []Window) []float64 {
	var out []float64
	for _, w := range windows {
		out = append(out, w.UsedPercent)
	}
	return out
}

// Swift: LimitsStatuslineTests.swift "regression: status line 76% used supersedes the old 62% cache"
func TestStatuslineSupersedesCache(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", accountState(defaultAcc))
	h.weekly("test-session", "76", statusNow)
	e := h.claude(statusNow)
	if e.Source == nil || *e.Source != ClaudeStatusline {
		t.Fatalf("source = %v", e.Source)
	}
	windows := wantMeasured(t, e)
	if *e.At != statusNow {
		t.Errorf("at = %v", *e.At)
	}
	if !slices.Equal(usedPercents(windows), []float64{76}) || windows[0].ID != "weekly_all" || ints(windows[0].Minutes) != "10080" {
		t.Errorf("windows = %+v", windows)
	}
	// S-R3: the result names no account, organization or key.
	data, _ := json.Marshal(h.read(statusNow))
	for _, secret := range []string{defaultAcc, "synthetic-org", h.accountKeyFor(defaultAcc, "synthetic-org")} {
		if strings.Contains(string(data), secret) {
			t.Errorf("result mentions %q", secret)
		}
	}
}

// Swift: LimitsStatuslineTests.swift "idle sessions cannot move usage backwards; a new reset window can"
func TestStatuslineIdleSessions(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", accountState(defaultAcc))
	h.weekly("active", "76", statusNow)
	h.weekly("idle", "62", statusNow+1)
	if got := usedPercents(wantMeasured(t, h.claude(statusNow+2))); !slices.Equal(got, []float64{76}) {
		t.Fatalf("idle session moved usage: %v", got)
	}
	h.snapshot("new-window", defaultAcc, statusNow+3, snapWindow{"seven_day", "1", reset + 604800})
	if got := usedPercents(wantMeasured(t, h.claude(statusNow+4))); !slices.Equal(got, []float64{1}) {
		t.Fatalf("new reset window: %v", got)
	}
}

// Swift: LimitsStatuslineTests.swift "a later partial payload keeps both recent windows, fractional usage and exact resets"
func TestStatuslineIndependentWindows(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", accountState(defaultAcc))
	h.snapshot("both", defaultAcc, statusNow, snapWindow{"five_hour", "95.5", reset - 1000}, snapWindow{"seven_day", "76.25", reset})
	h.weekly("partial", "62", statusNow+1)
	windows := wantMeasured(t, h.claude(statusNow+2))
	var ids []string
	var resets []float64
	var minutes []string
	for _, w := range windows {
		ids = append(ids, w.ID)
		resets = append(resets, w.ResetsAt)
		minutes = append(minutes, ints(w.Minutes))
	}
	if !slices.Equal(ids, []string{"five_hour", "weekly_all"}) || !slices.Equal(minutes, []string{"300", "10080"}) ||
		!slices.Equal(usedPercents(windows), []float64{95.5, 76.25}) || !slices.Equal(resets, []float64{reset - 1000, reset}) {
		t.Errorf("windows = %+v", windows)
	}
}

// Swift: LimitsStatuslineTests.swift "a newer usage-cache fetch supersedes an older status-line snapshot"
func TestStatuslineNewerCacheWins(t *testing.T) {
	h := newTempHome(t)
	cacheTime := statusNow + 10
	text := strings.Replace(accountState(defaultAcc), "1793800000000", fmt.Sprintf("%.0f", cacheTime*1000), 1)
	h.write(".claude/.claude.json", text)
	h.weekly("test-session", "76", statusNow)
	e := h.claude(statusNow + 20)
	if e.Source == nil || *e.Source != ClaudeCache {
		t.Fatalf("source = %v", e.Source)
	}
	windows := wantMeasured(t, e)
	if *e.At != cacheTime || !slices.Equal(usedPercents(windows), []float64{62}) {
		t.Errorf("at %v windows %+v", *e.At, windows)
	}
}

// Swift: LimitsStatuslineTests.swift "account switches reject previous snapshots and prevent an old session relabeling its quota"
// (read side: the snapshots are already on disk).
func TestStatuslineAccountSwitch(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", accountState("another-account"))
	h.weekly("test-session", "76", statusNow) // written under defaultAcc
	if e := h.claude(statusNow + 2); e.Source == nil || *e.Source != ClaudeCache {
		t.Fatalf("an old account's snapshot was used: %v", e.Source)
	}
	h.snapshot("new-login", "another-account", statusNow+3, snapWindow{"seven_day", "5", reset})
	if e := h.claude(statusNow + 4); e.Source == nil || *e.Source != ClaudeStatusline {
		t.Fatalf("the new login's snapshot was not used: %v", e.Source)
	}
}

// Swift: LimitsStatuslineTests.swift "malformed, future and special-file snapshots fall back without blocking"
func TestStatuslineInvalidFiles(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", accountState(defaultAcc))
	h.write(".spacevibe/claude-limits/invalid.json", "{bad")
	h.write(".spacevibe/claude-limits/large.json", strings.Repeat(" ", 5000))
	mkfifo(t, h.path(".spacevibe/claude-limits/fifo.json"))
	h.weekly("test-session", "76", statusNow+60) // observed after `now`: a future snapshot is ignored
	done := make(chan Entry, 1)
	go func() { done <- h.claude(statusNow) }()
	select {
	case e := <-done:
		if e.Source == nil || *e.Source != ClaudeCache {
			t.Fatalf("source = %v", e.Source)
		}
	case <-after5s():
		t.Fatal("Read blocked on a special file")
	}
}

// Swift: LimitsStatuslineTests.swift "managed subdirectory links cannot redirect collector or installer writes"
// (read side: a claude-limits link out of the data folder is not read either).
func TestStatuslineManagedDirectoryLinkIsNotRead(t *testing.T) {
	h := newTempHome(t)
	outside := newTempHome(t)
	h.write(".claude/.claude.json", accountState(defaultAcc))
	// A valid snapshot for this home's account, placed behind the link.
	key := h.accountKeyFor(defaultAcc, "synthetic-org")
	outside.write("snap.json", fmt.Sprintf(`{"account":"%s","observedAt":%v,"rate_limits":{"seven_day":{"used_percentage":76,"resets_at":%d}}}`, key, statusNow, reset))
	h.mkdir(".spacevibe")
	if err := os.Symlink(outside.root, h.path(".spacevibe/claude-limits")); err != nil {
		t.Skipf("no symlinks: %v", err)
	}
	if got := SnapshotFiles(h.cfg(), h.roots()); len(got) != 0 {
		t.Fatalf("files behind a link: %v", got)
	}
	if e := h.claude(statusNow + 1); e.Source == nil || *e.Source != ClaudeCache {
		t.Fatalf("source = %v", e.Source)
	}
}

func TestSnapshotFilesNamesAndOrder(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/.claude.json", accountState(defaultAcc))
	older := h.snapshot("a-old", defaultAcc, statusNow, snapWindow{"seven_day", "1", reset})
	newer := h.snapshot("b_new-1", defaultAcc, statusNow+5, snapWindow{"seven_day", "1", reset})
	h.write(".spacevibe/claude-limits/bad name.json", "{}")
	h.write(".spacevibe/claude-limits/notes.txt", "{}")
	h.write(".spacevibe/claude-limits/.json", "{}") // an empty stem passes, as in Swift
	setModified(t, h.path(".spacevibe/claude-limits/.json"), statusNow-10)
	if err := os.Mkdir(h.path(".spacevibe/claude-limits/dir.json"), 0o755); err != nil {
		t.Fatal(err)
	}
	got := SnapshotFiles(h.cfg(), h.roots())
	want := []string{newer, older, h.path(".spacevibe/claude-limits/.json")}
	if !slices.Equal(got, want) {
		t.Fatalf("files = %v, want %v", got, want)
	}
}

// Swift: LimitsStatuslineTests.swift "missing quota, invalid input and a partial malformed reading cannot overwrite a snapshot",
// the validation part: parseWindows throws for each of these.
func TestParseWindows(t *testing.T) {
	parse := func(text string) ([]Window, error) {
		doc, err := ojson.ParseString(text)
		if err != nil {
			t.Fatal(err)
		}
		return ParseWindows(doc.Root())
	}
	for _, bad := range []string{
		`{"seven_day":{"used_percentage":101,"resets_at":1794000000}}`,
		`{"seven_day":{"used_percentage":-1,"resets_at":1794000000}}`,
		`{"seven_day":{"used_percentage":76,"resets_at":0}}`,
		`{"seven_day":{"used_percentage":76,"resets_at":1794000000.5}}`,
		`{"seven_day":{"used_percentage":76,"resets_at":253402300800}}`,
		`{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":76,"resets_at":1794000000}}`,
		`{"seven_day":"76"}`,
		`[]`,
		`null`,
	} {
		if _, err := parse(bad); err == nil {
			t.Errorf("%s was accepted", bad)
		}
	}
	windows, err := parse(`{"seven_day":{"used_percentage":0,"resets_at":1794000000,"extra":"drop"},"five_hour":null,"other":1}`)
	if err != nil || len(windows) != 1 || windows[0].ID != "weekly_all" || windows[0].UsedPercent != 0 {
		t.Errorf("windows %+v err %v", windows, err)
	}
	if windows, err := parse(`{}`); err != nil || len(windows) != 0 {
		t.Errorf("empty object: %+v %v", windows, err)
	}
}

func TestAccountKey(t *testing.T) {
	h := newTempHome(t)
	if _, ok := AccountKey(h.roots()); ok {
		t.Fatal("no state file must give no key")
	}
	h.write(".claude/.claude.json", `{"oauthAccount":{"accountUuid":"a1","organizationUuid":"o1"}}`)
	key, ok := AccountKey(h.roots())
	want := hashes.SHA256Hex([]byte(h.path(".claude") + "\na1\no1"))
	if !ok || key != want {
		t.Fatalf("key %q ok %v, want %q", key, ok, want)
	}
	h.write(".claude/.claude.json", `{"oauthAccount":{"accountUuid":"a1"}}`)
	if key, _ := AccountKey(h.roots()); key != hashes.SHA256Hex([]byte(h.path(".claude")+"\na1\n")) {
		t.Errorf("a missing organization counts as empty, got %q", key)
	}
	for _, text := range []string{`{}`, `{"oauthAccount":{"accountUuid":""}}`, `{"oauthAccount":{"accountUuid":5}}`, `{"oauthAccount":5}`, `not json`} {
		h.write(".claude/.claude.json", text)
		if _, ok := AccountKey(h.roots()); ok {
			t.Errorf("%s gave a key", text)
		}
	}
}

func TestSessionIDSyntax(t *testing.T) {
	for s, want := range map[string]bool{"abc-DEF_09": true, "": true, "../escape": false, "a b": false, "é": false, "a.json": false} {
		if got := SessionIDSyntax(s); got != want {
			t.Errorf("%q: %v", s, got)
		}
	}
}
