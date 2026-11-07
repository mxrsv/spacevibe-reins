package usage

import (
	"bytes"
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
)

// swiftCache is usage-cache.json as the Swift engine's UsageScanCache.save wrote it (JSONEncoder, no
// formatting) for the three logs writeSwiftLogs builds (recorded by building ReinsCore with the 6.3
// toolchain and scanning that tree). It is the literal the plan asks for (G2.1): the Swift encoder writes compact
// JSON, escapes "/" as "\/", leaves out a nil `first`, and writes the members of every object in an order
// that changes from run to run (a Dictionary), so the order below is one of many it can produce. The root of
// the temp home is the placeholder @ROOT@ (written "/"-escaped in the literal).
const swiftCache = `{"@ROOT@\/.claude\/projects\/p\/s2.jsonl":{"session":"s2","stamp":"8:1791169200000","cli":"claude","v":2,"rec":{"agent":{},"hook":{},"skill":{}}},"@ROOT@\/.codex\/sessions\/2026\/rollout-a.jsonl":{"cli":"codex","rec":{"hook":{},"skill":{"cx-skill":["2026-10-04"]},"agent":{"explorer":["2026-10-04"]}},"stamp":"169:1791169200000","first":"2026-10-04","v":2,"session":"rollout-a"},"@ROOT@\/.claude\/projects\/p\/s1.jsonl":{"rec":{"skill":{"foo":["2026-10-02","2026-10-03"]},"hook":{"43c00ce9a764":{"errors":1,"ms":0,"last":"2026-10-02","runs":1,"timed":0},"6ee638a9ec1f":{"errors":0,"ms":12.5,"last":"2026-10-01","runs":1,"timed":1}},"agent":{"rev":["2026-10-03"]}},"stamp":"615:1791169200000","v":2,"cli":"claude","first":"2026-10-01","session":"s1"}}`

func escapedRoot(root string) string { return strings.ReplaceAll(root, "/", `\/`) }

// writeSwiftLogs writes the three logs behind swiftCache, byte for byte (sizes 615, 8 and 169).
func writeSwiftLogs(h tempHome) {
	h.write(".claude/projects/p/s1.jsonl", lines(
		`{"type":"attachment","timestamp":"2026-10-01T10:00:00Z","attachment":{"type":"hook_success","hookEvent":"Stop","command":"cmd-a","durationMs":12.5,"exitCode":0}}`,
		`{"type":"attachment","timestamp":"2026-10-02T10:00:00Z","attachment":{"type":"hook_non_blocking_error","hookEvent":"Stop","command":"cmd-b"}}`,
		`{"type":"assistant","timestamp":"2026-10-02T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"acme:foo"}}]}}`,
		`{"type":"assistant","timestamp":"2026-10-03T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"foo"},"x":{"subagent_type":"rev"}}]}}`,
	)+"\n")
	h.write(".claude/projects/p/s2.jsonl", "{\"x\":1}\n")
	h.write(".codex/sessions/2026/rollout-a.jsonl", `{"timestamp":"2026-10-04T10:00:00Z","type":"response_item","payload":{"type":"function_call","arguments":"cat skills/cx-skill/SKILL.md {\"agent_type\": \"explorer\"}"}}`+"\n")
	stamp := time.Unix(1791169200, 0)
	for _, rel := range []string{".claude/projects/p/s1.jsonl", ".claude/projects/p/s2.jsonl", ".codex/sessions/2026/rollout-a.jsonl"} {
		if err := os.Chtimes(h.path(rel), stamp, stamp); err != nil {
			h.t.Fatal(err)
		}
	}
}

func decodeTree(t *testing.T, data []byte) any {
	t.Helper()
	var v any
	if err := json.Unmarshal(data, &v); err != nil {
		t.Fatalf("not JSON: %v", err)
	}
	return v
}

// Extra (G2.1): the cache is shared by both engines while they coexist (UsageScanCache.swift:3-16). A cache
// written by Go for the same logs holds the same data as one the Swift engine wrote, in the same layout, and
// Go reads the Swift one back.
func TestCacheFormatMatchesSwift(t *testing.T) {
	h := newTempHome(t)
	writeSwiftLogs(h)
	r := h.roots()
	want := strings.ReplaceAll(swiftCache, "@ROOT@", escapedRoot(h.root))

	mustScan(t, NewScanner(r))
	got, err := os.ReadFile(CachePath(r.Data))
	if err != nil {
		t.Fatal(err)
	}

	// Same data: the member order of a Swift Dictionary encoding is random, so compare the trees.
	if !reflect.DeepEqual(decodeTree(t, got), decodeTree(t, []byte(want))) {
		t.Errorf("Go cache differs from the Swift cache\n go: %s\nswift: %s", got, want)
	}
	// Same layout: compact, "/" written as "\/", no `first` for a log without a timestamp, no trailing newline.
	if bytes.ContainsAny(got, " \n\t") {
		t.Errorf("the cache has whitespace: %q", got)
	}
	if bytes.Contains(got, []byte(h.root)) || !bytes.Contains(got, []byte(escapedRoot(h.root))) {
		t.Errorf("paths are not written with escaped slashes: %q", got)
	}
	if n := strings.Count(string(got), `"first"`); n != 2 {
		t.Errorf(`"first" appears %d times, want 2 (the log without a timestamp has none)`, n)
	}
	// Go sorts the members, so the same logs always give the same bytes.
	mustScan(t, NewScanner(r))
	again, _ := os.ReadFile(CachePath(r.Data))
	if !bytes.Equal(got, again) {
		t.Error("two scans of the same logs wrote different cache bytes")
	}

	// Go reads the Swift literal: every entry is valid and carries the Swift values.
	loaded := loadCacheFromBytes(t, r.Data, want)
	if len(loaded) != 3 {
		t.Fatalf("loaded %d entries from the Swift cache, want 3", len(loaded))
	}
	s1 := loaded[h.path(".claude/projects/p/s1.jsonl")]
	if s1.V != 2 || s1.Stamp != "615:1791169200000" || s1.CLI != Claude || s1.Session != "s1" || s1.First == nil || *s1.First != "2026-10-01" {
		t.Errorf("s1 = %+v", s1)
	}
	if hk := s1.Rec.Hook["6ee638a9ec1f"]; hk.Ms != 12.5 || hk.Timed != 1 || hk.Runs != 1 || hk.Last == nil || *hk.Last != "2026-10-01" {
		t.Errorf("hook = %+v", hk)
	}
	if s2 := loaded[h.path(".claude/projects/p/s2.jsonl")]; s2.First != nil || s2.mtimeMs() != 1791169200000 {
		t.Errorf("s2 = %+v", s2)
	}
	// And a scan trusts it: the same Swift cache with the `foo` skill dropped from s1 (the log still names it)
	// yields no `foo`, so Go used the entry instead of parsing s1 again.
	trimmed := strings.Replace(want, `"skill":{"foo":["2026-10-02","2026-10-03"]}`, `"skill":{}`, 1)
	if trimmed == want {
		t.Fatal("the literal has no foo skill to drop")
	}
	loadCacheFromBytes(t, r.Data, trimmed)
	res := mustScan(t, NewScanner(r))
	if _, ok := res.Totals.Claude.Skill["foo"]; ok || res.Files != 3 || res.Totals.Codex.Skill["cx-skill"].Sessions != 1 {
		t.Errorf("the scan did not trust the Swift entries: %+v", res)
	}
}

func loadCacheFromBytes(t *testing.T, dataDir, text string) map[string]cachedFile {
	t.Helper()
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(CachePath(dataDir), []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
	return loadCache(dataDir)
}

// Extra (G2.1): number text of hook durations is what Swift's JSONEncoder wrote for the same Doubles
// (observed with the Swift 6.3 toolchain): 0, 12.5, 123456789, 0.1 and 1e+21 without a trailing ".0".
func TestCacheNumberText(t *testing.T) {
	rec := newFileRecord()
	for i, ms := range []float64{0, 12.5, 123456789, 0.1, 1e21} {
		rec.Hook[string(rune('a'+i))] = HookTotals{Runs: 1, Ms: ms, Timed: 1, Last: ptr("2026-10-01")}
	}
	got, err := encodeCache(map[string]cachedFile{"/p": {V: 2, Stamp: "1:2", CLI: Claude, Session: "s<&>é", Rec: rec}})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`"ms":0,`, `"ms":12.5,`, `"ms":123456789,`, `"ms":0.1,`, `"ms":1e+21,`, `"\/p"`, `"session":"s<&>é"`} {
		if !strings.Contains(string(got), want) {
			t.Errorf("cache lacks %s: %s", want, got)
		}
	}
}

// Extra (G2.1): the entry rules of Swift's synthesized Decodable: a member that is missing or null rejects
// its entry only; `first` and `last` are optional; an unknown CLI rejects the entry.
func TestCacheEntryValidation(t *testing.T) {
	h := newTempHome(t)
	entry := func(mutate string) string {
		return `{"v":2,"stamp":"1:2","cli":"claude","session":"s",` + mutate + `}`
	}
	good := `"rec":{"skill":{},"agent":{},"hook":{"h":{"runs":1,"ms":2,"timed":1,"errors":0}}}`
	text := `{"/ok":` + entry(good) + `,` +
		`"/no-agent":` + entry(`"rec":{"skill":{},"hook":{}}`) + `,` +
		`"/null-rec":` + entry(`"rec":null`) + `,` +
		`"/hook-no-runs":` + entry(`"rec":{"skill":{},"agent":{},"hook":{"h":{"ms":2,"timed":1,"errors":0}}}`) + `,` +
		`"/bad-cli":{"v":2,"stamp":"1:2","cli":"gemini","session":"s",` + good + `},` +
		`"/no-v":{"stamp":"1:2","cli":"claude","session":"s",` + good + `},` +
		`"/not-object":5}`
	loaded := loadCacheFromBytes(t, h.data(), text)
	if len(loaded) != 1 || loaded["/ok"].Rec.Hook["h"].Last != nil {
		t.Errorf("loaded = %+v, want only /ok (hook last nil)", loaded)
	}
	for _, bad := range []string{`[1,2]`, `5`, ``, `{`} {
		if got := loadCacheFromBytes(t, h.data(), bad); len(got) != 0 {
			t.Errorf("%q gave %d entries", bad, len(got))
		}
	}
}
