package statusline

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/goldentest"
	"spacevibe.dev/core/internal/limits"
)

// input is LimitsStatuslineTests.input: a status line payload with fields that must never be stored.
func input(used int, session string, resetAt int) []byte {
	return []byte(fmt.Sprintf(`{"session_id":"%s","secret":"must-not-persist","transcript_path":"private",
"rate_limits":{"seven_day":{"used_percentage":%d,"resets_at":%d,"extra":"drop"}}}`, session, used, resetAt))
}

func (h tempHome) capture(data []byte, now float64) error {
	h.t.Helper()
	return Capture(h.cfg(), h.roots(), data, at(now))
}

func (h tempHome) read(now float64) limits.Entry {
	h.t.Helper()
	result, err := limits.Read(h.t.Context(), h.cfg(), h.roots(), at(now))
	if err != nil {
		h.t.Fatal(err)
	}
	return result.Limits[0]
}

func (h tempHome) snapshots() []string { return limits.SnapshotFiles(h.cfg(), h.roots()) }

// Swift: LimitsStatuslineTests.swift "regression: status line 76% used supersedes the old 62% cache"
func TestCaptureSupersedesCache(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	if err := h.capture(input(76, "test-session", reset), statusNow); err != nil {
		t.Fatal(err)
	}
	e := h.read(statusNow)
	if e.Source == nil || *e.Source != limits.ClaudeStatusline || e.State != limits.Measured {
		t.Fatalf("entry = %+v", e)
	}
	if *e.At != statusNow || len(e.Windows) != 1 || e.Windows[0].UsedPercent != 76 || e.Windows[0].ID != "weekly_all" || *e.Windows[0].Minutes != 10080 {
		t.Fatalf("windows = %+v at %v", e.Windows, *e.At)
	}
	saved := h.read2(t)
	for _, leak := range []string{"must-not-persist", "transcript_path", "synthetic-account", "extra"} {
		if strings.Contains(saved, leak) {
			t.Errorf("the snapshot keeps %q:\n%s", leak, saved)
		}
	}
	if m := h.mode(".spacevibe/claude-limits/test-session.json"); m != 0o600 {
		t.Errorf("snapshot mode = %o, want 600", m)
	}
	if m := h.mode(".spacevibe/claude-limits"); m != 0o700 {
		t.Errorf("snapshot folder mode = %o, want 700", m)
	}
}

func (h tempHome) read2(t *testing.T) string {
	files := h.snapshots()
	if len(files) != 1 {
		t.Fatalf("snapshots = %v", files)
	}
	data, err := os.ReadFile(files[0])
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// Swift: LimitsStatuslineTests.swift "missing quota, invalid input and a partial malformed reading cannot overwrite a snapshot"
func TestCaptureInvalidInput(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	if err := h.capture(input(76, "test-session", reset), statusNow); err != nil {
		t.Fatal(err)
	}
	before := h.read2(t)
	if err := h.capture([]byte(`{"session_id":"test-session"}`), statusNow+1); err != nil {
		t.Fatalf("a payload without rate limits is normal, got %v", err)
	}
	invalid := map[string][]byte{
		"101 percent":       input(101, "test-session", reset),
		"-1 percent":        input(-1, "test-session", reset),
		"path in session":   input(76, "../escape", reset),
		"reset 0":           input(76, "test-session", 0),
		"over the cap":      make([]byte, limits.MaxInputBytes+1),
		"partial window":    []byte(`{"session_id":"test-session","rate_limits":{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":76,"resets_at":1794000000}}}`),
		"not json":          []byte(`{bad`),
		"no session":        []byte(`{"rate_limits":{}}`),
		"empty session":     input(76, "", reset),
		"session too long":  input(76, strings.Repeat("a", 129), reset),
		"rate_limits array": []byte(`{"session_id":"test-session","rate_limits":[]}`),
	}
	for name, data := range invalid {
		if err := h.capture(data, statusNow+2); err == nil {
			t.Errorf("%s: no error", name)
		}
	}
	if got := h.read2(t); got != before {
		t.Fatalf("a snapshot was overwritten:\n%s\n--\n%s", got, before)
	}
}

// Swift: LimitsStatuslineTests.swift "account switches reject previous snapshots and prevent an old session relabeling its quota"
func TestCaptureAccountSwitch(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	if err := h.capture(input(76, "test-session", reset), statusNow); err != nil {
		t.Fatal(err)
	}
	h.account("another-account")
	if err := h.capture(input(76, "test-session", reset), statusNow+1); err != nil {
		t.Fatal(err)
	}
	if e := h.read(statusNow + 2); *e.Source != limits.ClaudeCache {
		t.Fatalf("source = %v, want claudeCache: the old session must not relabel its quota", *e.Source)
	}
	if err := h.capture(input(5, "new-login", reset), statusNow+3); err != nil {
		t.Fatal(err)
	}
	if e := h.read(statusNow + 4); *e.Source != limits.ClaudeStatusline {
		t.Fatalf("source = %v, want claudeStatusline", *e.Source)
	}
}

// Swift: LimitsStatuslineTests.swift "a later partial payload keeps both recent windows, fractional usage and exact resets"
func TestCaptureIndependentWindows(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	both := fmt.Sprintf(`{"session_id":"both","rate_limits":{
 "five_hour":{"used_percentage":95.5,"resets_at":%d},"seven_day":{"used_percentage":76.25,"resets_at":%d}}}`, reset-1000, reset)
	if err := h.capture([]byte(both), statusNow); err != nil {
		t.Fatal(err)
	}
	if err := h.capture(input(62, "partial", reset), statusNow+1); err != nil {
		t.Fatal(err)
	}
	e := h.read(statusNow + 2)
	if len(e.Windows) != 2 || e.Windows[0].ID != "five_hour" || e.Windows[1].ID != "weekly_all" ||
		e.Windows[0].UsedPercent != 95.5 || e.Windows[1].UsedPercent != 76.25 {
		t.Fatalf("windows = %+v", e.Windows)
	}
	if *e.Windows[0].Minutes != 300 || *e.Windows[1].Minutes != 10080 {
		t.Fatalf("minutes = %d, %d", *e.Windows[0].Minutes, *e.Windows[1].Minutes)
	}
	if e.Windows[0].ResetsAt != float64(reset-1000) || e.Windows[1].ResetsAt != float64(reset) {
		t.Fatalf("resetsAt = %v, %v", e.Windows[0].ResetsAt, e.Windows[1].ResetsAt)
	}
}

// Swift: LimitsStatuslineTests.swift "managed subdirectory links cannot redirect collector or installer writes" (the collector half)
func TestCaptureManagedDirectoryLink(t *testing.T) {
	h := newTempHome(t)
	outside := newTempHome(t)
	h.account("synthetic-account")
	sentinel := outside.write("sentinel.json", "keep")
	if err := os.MkdirAll(h.path(".spacevibe"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside.root, h.path(".spacevibe/claude-limits")); err != nil {
		t.Fatal(err)
	}
	if err := h.capture(input(76, "test-session", reset), statusNow); err == nil {
		t.Fatal("capture wrote through a link")
	}
	recordFailure(h.cfg(), h.roots(), ReasonWriteFailed) // must refuse too
	entries, _ := os.ReadDir(outside.root)
	if len(entries) != 1 || entries[0].Name() != "sentinel.json" {
		t.Fatalf("the folder outside holds %v", entries)
	}
	if data, _ := os.ReadFile(sentinel); string(data) != "keep" {
		t.Fatalf("sentinel = %q", data)
	}
}

// Five sessions over the cap: the folder keeps the newest MaxSessions snapshots (the oldest five go) and never
// deletes a file it did not write.
func TestCaptureKeepsNewestSessions(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	h.write(".spacevibe/claude-limits/foreign.json", `{"not":"ours"}`)
	for i := 0; i < limits.MaxSessions+5; i++ {
		if err := h.capture(input(10, fmt.Sprintf("s%03d", i), reset), statusNow+float64(i)); err != nil {
			t.Fatal(err)
		}
	}
	// MaxSessions captured sessions plus the foreign file, which counts in the folder but is never pruned.
	if files := h.snapshots(); len(files) != limits.MaxSessions+1 {
		t.Fatalf("%d snapshots kept, want %d", len(files), limits.MaxSessions+1)
	}
	for i := 0; i < 5; i++ {
		if h.exists(fmt.Sprintf(".spacevibe/claude-limits/s%03d.json", i)) {
			t.Errorf("the oldest session s%03d was kept", i)
		}
	}
	if !h.exists(fmt.Sprintf(".spacevibe/claude-limits/s%03d.json", limits.MaxSessions+4)) {
		t.Error("the newest session was removed")
	}
	if !h.exists(".spacevibe/claude-limits/foreign.json") {
		t.Fatal("a file without an account was deleted")
	}
}

// G-fix.19: a failed capture leaves a fixed reason, a good one clears it, and nothing else is stored.
func TestLastError(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	last := ".spacevibe/claude-limits/" + limits.LastErrorFile
	if LastErrorPath(h.roots()) != h.path(last) {
		t.Fatalf("LastErrorPath = %s", LastErrorPath(h.roots()))
	}
	r, cfg := h.roots(), h.cfg()
	if got := collect2(h, []byte(`{bad`)); got != ReasonInvalidInput {
		t.Fatalf("reason = %q", got)
	}
	if h.text(last) != ReasonInvalidInput+"\n" || h.mode(last) != 0o600 {
		t.Fatalf("last-error = %q mode %o", h.text(last), h.mode(last))
	}
	if files := limits.SnapshotFiles(cfg, r); len(files) != 0 {
		t.Fatalf("last-error is listed as a snapshot: %v", files)
	}
	if got := collect2(h, input(76, "ok", reset)); got != "" {
		t.Fatalf("reason = %q", got)
	}
	if h.exists(last) {
		t.Fatal("last-error survived a good capture")
	}
	// The other reasons.
	cases := map[string]struct {
		data []byte
		want string
	}{
		"too large":  {make([]byte, limits.MaxInputBytes+1), ReasonInputTooLarge},
		"bad limits": {input(101, "ok", reset), ReasonInvalidLimits},
	}
	for name, c := range cases {
		if got := collect2(h, c.data); got != c.want {
			t.Errorf("%s: reason = %q, want %q", name, got, c.want)
		}
	}
	h.write(".claude/.claude.json", `{}`)
	if got := collect2(h, input(76, "ok", reset)); got != ReasonAccountUnknown {
		t.Errorf("no account: reason = %q", got)
	}
	if got := collect2(h, input(76, "ok", reset), h.path(".elsewhere")); got != ReasonClaudeRootChanged {
		t.Errorf("claude root: reason = %q", got)
	}
	if data := h.text(last); len(data) > 64 || strings.ContainsAny(strings.TrimSpace(data), " /\n") {
		t.Errorf("last-error is not a bare reason code: %q", data)
	}
}

// collect2 runs the capture command's collection step against h through the environment the command reads.
func collect2(h tempHome, data []byte, claudeRoot ...string) string {
	h.t.Helper()
	h.setEnv()
	root := h.path(".claude")
	if len(claudeRoot) > 0 {
		root = claudeRoot[0]
	}
	return collect(h.path(".spacevibe"), root, data, len(data) > limits.MaxInputBytes, false)
}

func (h tempHome) setEnv() {
	h.t.Helper()
	h.t.Setenv("SPACEVIBE_TEST", "1")
	h.t.Setenv("HOME", h.root)
	h.t.Setenv("CLAUDE_CONFIG_DIR", h.path(".claude"))
	h.t.Setenv("CODEX_HOME", h.path(".codex"))
	h.t.Setenv("SPACEVIBE_HOME", "")
}

// Swift: LimitsGoldenTests.swift "the status line snapshot the cases write by hand is what the collector writes".
// The hand-written text is the one in the frozen limits.json golden, so the cases there and this collector agree.
func TestSnapshotShapeMatchesCapture(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	in := `{"session_id":"s1","rate_limits":{"seven_day":{"used_percentage":76,"resets_at":1794000000}}}`
	if err := h.capture([]byte(in), 1_793_900_000.0); err != nil {
		t.Fatal(err)
	}
	written := h.read2(t)

	golden, err := goldentest.LoadGolden("limits")
	if err != nil {
		t.Fatal(err)
	}
	const token = "$ACCOUNT_KEY(synthetic-account,synthetic-org)"
	byHand := findText(golden, token)
	if byHand == "" {
		t.Fatal("the golden has no hand-written snapshot")
	}
	key, ok := limits.AccountKey(h.roots())
	if !ok {
		t.Fatal("no account key")
	}
	var a, b any
	if err := json.Unmarshal([]byte(written), &a); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(strings.ReplaceAll(byHand, token, key)), &b); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(a, b) {
		t.Fatalf("collector wrote\n%s\nthe golden case writes\n%s", written, byHand)
	}
	if !strings.Contains(written, `"observedAt": 1793900000.0`) {
		t.Errorf("observedAt is not spelled like Swift's Double: %s", written)
	}
}

// findText is the first string in the golden tree that holds token and the seven-day 76% snapshot at the default time.
func findText(v any, token string) string {
	switch x := v.(type) {
	case string:
		if strings.Contains(x, token) && strings.Contains(x, `"observedAt":1793900000.0`) && strings.Contains(x, `"used_percentage":76`) {
			return x
		}
	case []any:
		for _, e := range x {
			if s := findText(e, token); s != "" {
				return s
			}
		}
	case map[string]any:
		for _, e := range x {
			if s := findText(e, token); s != "" {
				return s
			}
		}
	}
	return ""
}

func TestSeconds(t *testing.T) {
	for in, want := range map[float64]string{1_793_900_000: "1793900000.0", 1_793_900_000.5: "1793900000.5", 1_793_900_001.25: "1793900001.25"} {
		if got := seconds(at(in)); got != want {
			t.Errorf("seconds(%v) = %s, want %s", in, got, want)
		}
	}
	if bytes.Contains([]byte(seconds(at(1))), []byte("e")) {
		t.Error("exponent")
	}
}
