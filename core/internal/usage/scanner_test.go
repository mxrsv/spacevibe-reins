package usage

import (
	"context"
	"errors"
	"os"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/hashes"
	"spacevibe.dev/core/internal/roots"
)

func hookOf(r Result, event, command string) (HookTotals, bool) {
	h, ok := r.Totals.Claude.Hook[hashes.HookHash(event, command)]
	return h, ok
}

// Swift: UsageScanTests.swift "hook errors are counted for every error record shape, per event plus command"
func TestHookErrors(t *testing.T) {
	h := newTempHome(t)
	text := lines(
		attach("2026-10-01", map[string]any{"type": "hook_success", "hookEvent": "Stop", "hookName": "Stop", "command": "cmd-a", "durationMs": 10, "exitCode": 0, "stdout": "", "stderr": ""}),
		attach("2026-10-02", map[string]any{"type": "hook_non_blocking_error", "hookEvent": "Stop", "hookName": "Stop", "command": "cmd-a", "durationMs": 20, "exitCode": 1, "stdout": "", "stderr": "boom"}),
		attach("2026-10-03", map[string]any{"type": "hook_success", "hookEvent": "Stop", "hookName": "Stop", "command": "cmd-a", "durationMs": 30, "exitCode": 2}),
		// The blocking error carries the command inside blockingError, not at the top level.
		attach("2026-10-04", map[string]any{"type": "hook_blocking_error", "hookEvent": "PostToolUse", "hookName": "PostToolUse:Edit", "toolUseID": "t1", "blockingError": map[string]any{"blockingError": "denied", "command": "cmd-b"}}),
		attach("2026-10-05", map[string]any{"type": "hook_blocking_error", "hookEvent": "PostToolUse", "hookName": "PostToolUse:Edit", "toolUseID": "t2", "blockingError": map[string]any{"blockingError": "denied", "command": "cmd-b"}}),
		// Same command under another event is another hook.
		attach("2026-10-05", map[string]any{"type": "hook_success", "hookEvent": "PreToolUse", "command": "cmd-b", "durationMs": 5, "exitCode": 0}),
		// Quoted text and a record without a command are not runs; neither is a boolean duration a duration.
		`{"type":"user","timestamp":"2026-10-05T10:00:00Z","message":{"content":"hook_blocking_error \"command\":\"cmd-a\""}}`,
		attach("2026-10-05", map[string]any{"type": "hook_additional_context", "hookEvent": "Stop", "content": map[string]any{}}),
		`{"type":"attachment","timestamp":"2026-10-06T10:00:00Z","attachment":{"type":"hook_success","hookEvent":"Stop","command":"cmd-c","durationMs":true,"exitCode":false}}`,
	)
	h.write(".claude/projects/p/s1.jsonl", text)
	result := scan(t, h)
	a, _ := hookOf(result, "Stop", "cmd-a")
	if want := (HookTotals{Runs: 3, Ms: 60, Timed: 3, Errors: 2, Last: ptr("2026-10-03")}); !reflect.DeepEqual(a, want) {
		t.Errorf("cmd-a = %+v, want %+v", a, want)
	}
	if b, _ := hookOf(result, "PostToolUse", "cmd-b"); b.Runs != 2 || b.Errors != 2 {
		t.Errorf("PostToolUse cmd-b = %+v", b)
	}
	if b, _ := hookOf(result, "PreToolUse", "cmd-b"); b.Runs != 1 || b.Errors != 0 {
		t.Errorf("PreToolUse cmd-b = %+v", b)
	}
	c, _ := hookOf(result, "Stop", "cmd-c")
	if want := (HookTotals{Runs: 1, Last: ptr("2026-10-06")}); !reflect.DeepEqual(c, want) {
		t.Errorf("cmd-c = %+v, want %+v", c, want)
	}
	if n := len(result.Totals.Claude.Hook); n != 4 {
		t.Errorf("hook count = %d, want 4", n)
	}
}

// A hookEvent that is missing, null or a number still gives the hook an identity, as `${value}` does.
func TestHookEventIdentityText(t *testing.T) {
	h := newTempHome(t)
	rec := func(event string) string {
		return `{"type":"attachment","timestamp":"2026-10-01T10:00:00Z","attachment":{"type":"hook_success",` + event + `"command":"c"}}`
	}
	h.write(".claude/projects/p/s1.jsonl", lines(rec(``), rec(`"hookEvent":null,`), rec(`"hookEvent":7,`), rec(`"hookEvent":{"a":1},`), rec(`"hookEvent":true,`)))
	r := scan(t, h)
	for _, event := range []string{"undefined", "null", "7", "[object Object]", "true"} {
		if _, ok := hookOf(r, event, "c"); !ok {
			t.Errorf("no hook for event text %q", event)
		}
	}
}

// Swift: UsageScanTests.swift "skills, slash commands and subagents count sessions, not mentions; plugin prefixes are dropped"
func TestSkillsAndAgents(t *testing.T) {
	h := newTempHome(t)
	skillCall := func(day, name string) string {
		return `{"type":"assistant","timestamp":"` + day + `T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"` + name + `"}}]}}`
	}
	slash := func(day, name string) string {
		return `{"type":"user","timestamp":"` + day + `T10:00:00Z","message":{"content":"<command-name>/` + name + `</command-name>"}}`
	}
	agent := func(day, name string) string {
		return `{"type":"assistant","timestamp":"` + day + `T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"` + name + `"}}]}}`
	}
	h.write(".claude/projects/p/s1.jsonl", lines(skillCall("2026-10-01", "acme:foo"), skillCall("2026-10-01", "foo"), slash("2026-10-02", "bar"), agent("2026-10-02", "rev")))
	h.write(".claude/projects/p/s2.jsonl", lines(skillCall("2026-10-04", "foo"), agent("2026-10-04", "rev")))
	// A subagent log belongs to the session that spawned it.
	h.write(".claude/projects/p/s2/subagents/agent-1.jsonl", skillCall("2026-10-05", "foo"))
	r := scan(t, h)
	want := NameUsage{Sessions: 2, Days: []string{"2026-10-01", "2026-10-04", "2026-10-05"}, Last: ptr("2026-10-05")}
	if got := r.Totals.Claude.Skill["foo"]; !reflect.DeepEqual(got, want) {
		t.Errorf("foo = %+v, want %+v", got, want)
	}
	if r.Totals.Claude.Skill["bar"].Sessions != 1 {
		t.Errorf("bar = %+v", r.Totals.Claude.Skill["bar"])
	}
	if r.Totals.Claude.Agent["rev"].Sessions != 2 {
		t.Errorf("rev = %+v", r.Totals.Claude.Agent["rev"])
	}
	if r.Sessions != (Sessions{Claude: 2}) || r.Files != 3 {
		t.Errorf("sessions %+v files %d", r.Sessions, r.Files)
	}
}

// Swift: UsageScanTests.swift "the log window is reported per CLI; a cache entry from an older parser is scanned again"
func TestWindowAndCacheVersion(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/projects/p/s1.jsonl", attach("2026-10-01", map[string]any{"type": "hook_blocking_error", "hookEvent": "PostToolUse", "blockingError": map[string]any{"command": "cmd-b"}}))
	r := h.roots()
	first := mustScan(t, NewScanner(r))
	if w := first.Windows.Claude; w.Files != 1 || w.Oldest == nil || *w.Oldest != "2026-10-01" || w.Newest == nil || *w.Newest <= 0 {
		t.Errorf("claude window = %+v", w)
	}
	if first.Windows.Codex != (LogWindow{}) {
		t.Errorf("codex window = %+v", first.Windows.Codex)
	}

	// The cache lives under the data root and carries the version.
	if got, want := CachePath(r.Data), h.data()+"/usage-cache.json"; got != want {
		t.Errorf("cache path %q, want %q", got, want)
	}
	cache := loadCache(r.Data)
	var key string
	var entry cachedFile
	for key, entry = range cache {
	}
	if len(cache) != 1 || entry.V != ScanVersion {
		t.Fatalf("cache = %+v", cache)
	}

	// A cache entry of the right version and stamp is trusted (no reparse) ...
	trusted := entry
	trusted.Rec = newFileRecord()
	saveCache(map[string]cachedFile{key: trusted}, r.Data)
	if got := mustScan(t, NewScanner(r)); len(got.Totals.Claude.Hook) != 0 {
		t.Errorf("a trusted entry was parsed again: %+v", got.Totals.Claude.Hook)
	}
	// ... and one written by an older parser is not.
	old := trusted
	old.V = ScanVersion - 1
	saveCache(map[string]cachedFile{key: old}, r.Data)
	again := mustScan(t, NewScanner(r))
	if hk, _ := hookOf(again, "PostToolUse", "cmd-b"); hk.Errors != 1 {
		t.Errorf("an old entry was not scanned again: %+v", hk)
	}
}

// Swift: UsageScanTests.swift "a corrupt cache file is an empty cache; the cache is private to the user"
func TestCorruptCache(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/projects/p/s1.jsonl", attach("2026-10-01", map[string]any{"type": "hook_success", "hookEvent": "Stop", "command": "c"}))
	h.write(".spacevibe/usage-cache.json", "{ truncated")
	r := h.roots()
	result := mustScan(t, NewScanner(r))
	if len(result.Totals.Claude.Hook) != 1 {
		t.Errorf("hooks = %+v", result.Totals.Claude.Hook)
	}
	info, err := os.Stat(CachePath(r.Data))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("cache mode %o, want 600", info.Mode().Perm())
	}
	if dir, _ := os.Stat(r.Data); dir.Mode().Perm() != 0o755 && dir.Mode().Perm() != 0o700 {
		t.Errorf("data dir mode %o", dir.Mode().Perm())
	}
}

// Swift: UsageScanTests.swift "compressed Codex rollouts count like plain ones, and a session in both forms counts once"
func TestCompressedRollouts(t *testing.T) {
	h := newTempHome(t)
	dir := ".codex/sessions/2026/03/01"
	h.write(dir+"/rollout-old.jsonl.zst", zstdRawFrame([]byte(codexCall("2026-03-01", "old-skill"))))
	h.write(dir+"/rollout-both.jsonl", codexCall("2026-03-02", "both-skill"))
	h.write(dir+"/rollout-both.jsonl.zst", zstdRawFrame([]byte(codexCall("2026-03-02", "stale-skill"))))
	h.write(dir+"/rollout-broken.jsonl.zst", "not zstd")
	r := scan(t, h)
	if want := (NameUsage{Sessions: 1, Days: []string{"2026-03-01"}, Last: ptr("2026-03-01")}); !reflect.DeepEqual(r.Totals.Codex.Skill["old-skill"], want) {
		t.Errorf("old-skill = %+v", r.Totals.Codex.Skill["old-skill"])
	}
	if r.Totals.Codex.Skill["both-skill"].Sessions != 1 {
		t.Errorf("both-skill = %+v", r.Totals.Codex.Skill["both-skill"])
	}
	if _, ok := r.Totals.Codex.Skill["stale-skill"]; ok {
		t.Error("the compressed twin of a plain log was read")
	}
	if r.Sessions.Codex != 2 {
		t.Errorf("codex sessions = %d, want 2 (the broken file is skipped, the others still count)", r.Sessions.Codex)
	}
	if r.Files != 3 {
		t.Errorf("files = %d, want 3", r.Files)
	}
	if r.Windows.Codex.Oldest == nil || *r.Windows.Codex.Oldest != "2026-03-01" {
		t.Errorf("codex window = %+v", r.Windows.Codex)
	}
}

// Swift: UsageScanTests.swift "Codex agents and skills are read from tool calls only"
func TestCodexCalls(t *testing.T) {
	h := newTempHome(t)
	call := `{"timestamp":"2026-10-01T10:00:00Z","type":"response_item","payload":{"type":"function_call","arguments":"{\"agent_type\": \"explorer\"}"}}` + "\n"
	chatter := `{"timestamp":"2026-10-01T10:00:00Z","type":"event_msg","payload":{"message":"please read skills/chat-only/SKILL.md and agent_type explorer"}}` + "\n"
	h.write(".codex/sessions/2026/10/rollout-a.jsonl", call+chatter)
	r := scan(t, h)
	if r.Totals.Codex.Agent["explorer"].Sessions != 1 {
		t.Errorf("explorer = %+v", r.Totals.Codex.Agent["explorer"])
	}
	if _, ok := r.Totals.Codex.Skill["chat-only"]; ok {
		t.Error("a skill named in chatter was counted")
	}
}

// Swift: UsageScanTests.swift "an unreadable log, an oversized line, an empty file and binary junk never crash the scan"
func TestHostileLogs(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root ignores permission bits")
	}
	h := newTempHome(t)
	h.write(".claude/projects/p/empty.jsonl", "")
	h.write(".claude/projects/p/junk.jsonl", []byte{0xFF, 0x00, 0xFE, 0x0A, 0x7B, 0x0A})
	denied := h.write(".claude/projects/p/denied.jsonl", attach("2026-10-01", map[string]any{"type": "hook_success", "hookEvent": "Stop", "command": "c"}))
	if err := os.Chmod(denied, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(denied, 0o644) })
	const limit = 4096
	huge := `{"type":"user","x":"` + strings.Repeat("y", limit+10) + `"}` + "\n"
	h.write(".claude/projects/p/huge.jsonl", huge+attach("2026-10-02", map[string]any{"type": "hook_success", "hookEvent": "Stop", "command": "after-huge"}))
	s := NewScanner(h.roots())
	s.MaxLineBytes = limit
	r := mustScan(t, s)
	if r.Files != 4 {
		t.Errorf("files = %d, want 4", r.Files)
	}
	if hk, _ := hookOf(r, "Stop", "after-huge"); hk.Runs != 1 {
		t.Errorf("the line after the oversized one was lost: %+v", hk)
	}
}

// Swift: UsageScanTests.swift "progress is reported and ends at the file count; cancelling throws and writes no cache"
func TestProgressAndCancel(t *testing.T) {
	h := newTempHome(t)
	for i := range 45 {
		h.write(".claude/projects/p/s"+strconv.Itoa(i)+".jsonl", "{}\n")
	}
	r := h.roots()
	var seen []Progress
	if _, err := NewScanner(r).Scan(t.Context(), func(p Progress) { seen = append(seen, p) }); err != nil {
		t.Fatal(err)
	}
	if last := seen[len(seen)-1]; last != (Progress{Done: 45, Total: 45}) {
		t.Errorf("last progress = %+v", last)
	}
	if len(seen) < 3 {
		t.Errorf("progress calls = %d, want at least 3 (every %d files and the end)", len(seen), ProgressEvery)
	}
	for i := 1; i < len(seen); i++ {
		if seen[i-1].Done > seen[i].Done {
			t.Errorf("progress went backwards: %+v", seen)
		}
	}
	// Every 20 files, then the end: 20, 40, 45.
	if want := []Progress{{20, 45}, {40, 45}, {45, 45}}; !reflect.DeepEqual(seen, want) {
		t.Errorf("progress = %+v, want %+v", seen, want)
	}

	if err := os.Remove(CachePath(r.Data)); err != nil {
		t.Fatal(err)
	}
	// Cancelled before the first file is read, so the outcome does not depend on timing.
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	scanner := NewScanner(r)
	if _, err := scanner.Scan(ctx, nil); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
	if _, err := os.Stat(CachePath(r.Data)); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("a cancelled scan left a cache behind: %v", err)
	}
	if _, ok := scanner.Last(); ok {
		t.Error("a cancelled scan stored a result")
	}
}

// Extra (G2.1): a cancel that arrives after some files were scanned leaves the cache exactly as it was.
func TestCancelMidScanKeepsCache(t *testing.T) {
	h := newTempHome(t)
	for i := range 25 {
		h.write(".claude/projects/p/s"+strconv.Itoa(i)+".jsonl", "{}\n")
	}
	r := h.roots()
	before := []byte("{}")
	h.write(".spacevibe/usage-cache.json", before)
	ctx, cancel := context.WithCancel(t.Context())
	_, err := NewScanner(r).Scan(ctx, func(Progress) { cancel() }) // first callback is after file 20
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
	got, _ := os.ReadFile(CachePath(r.Data))
	if string(got) != string(before) {
		t.Errorf("cache changed by a cancelled scan: %q", got)
	}
}

// Extra (G2.1): a second scan while one runs is a 409 and a finished scan is remembered.
func TestOneScanAtATime(t *testing.T) {
	h := newTempHome(t)
	h.write(".claude/projects/p/s1.jsonl", "{}\n")
	s := NewScanner(h.roots())
	var inner error
	_, err := s.Scan(t.Context(), func(Progress) { _, inner = s.Scan(t.Context(), nil) })
	if err != nil {
		t.Fatal(err)
	}
	ce, ok := coreerr.As(inner)
	if !ok || ce.Status != coreerr.StatusConflict {
		t.Errorf("nested scan error = %v, want a 409", inner)
	}
	if last, ok := s.Last(); !ok || last.Files != 1 {
		t.Errorf("Last = %+v, %v", last, ok)
	}
}

// Swift: UsageScanTests.swift "the scan never reads the real home: the roots it is given are the temp ones, and the guard refuses the real ones"
func TestNeverTouchesRealHome(t *testing.T) {
	h := newTempHome(t)
	r := h.roots()
	for _, p := range []string{r.Claude.Logs, r.Codex.Logs, CachePath(r.Data)} {
		if !strings.HasPrefix(p, h.root) {
			t.Errorf("%q is outside the temp home", p)
		}
	}
	real, err := roots.RealHome()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := roots.Resolve(config.Config{Test: true, UserHome: real}, real); err == nil {
		t.Error("a root under the real home was accepted")
	}
}

// Extra (G2.1), H14: Swift Dictionary keys and Set members use canonical equivalence, so the same skill name
// in NFC and NFD form is one entry there. Go compares bytes: two entries, one session each. (Swift, observed
// with the 6.3 toolchain on the same two logs: one entry "café" with 2 sessions.) Folding them would need
// Unicode normalization tables, which the standard library does not have; see the report of G2.1.
func TestNFDNamesStaySeparateInGo(t *testing.T) {
	h := newTempHome(t)
	call := func(name string) string {
		return `{"type":"assistant","timestamp":"2026-10-01T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"` + name + `"}}]}}` + "\n"
	}
	nfc, nfd := "café", "café"
	h.write(".claude/projects/p/s1.jsonl", call(nfc))
	h.write(".claude/projects/p/s2.jsonl", call(nfd))
	r := scan(t, h)
	if len(r.Totals.Claude.Skill) != 2 || r.Totals.Claude.Skill[nfc].Sessions != 1 || r.Totals.Claude.Skill[nfd].Sessions != 1 {
		t.Errorf("skills = %+v, want the NFC and NFD names apart with 1 session each", r.Totals.Claude.Skill)
	}
}
