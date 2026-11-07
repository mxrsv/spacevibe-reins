package activity

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/goldentest"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// The frozen goldens activity.json and activity-proc.json (SV5), compared through the projection "activity-oracle":
// sessions by cli|id, failures by cli|kind|key, files by path, Codex `pid:<pid>:<start>` read back as `pid:<pid>`,
// stats {logs, truncated}. Swift: ActivityGoldenTests.swift.

// decode reads JSON into a generic tree with numbers kept as json.Number.
func decode(t *testing.T, data []byte) any {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		t.Fatal(err)
	}
	return v
}

// oracleProjection is the activity-oracle projection of an encoded report (or of a golden section).
func oracleProjection(report map[string]any) map[string]any {
	sortedBy := func(items any, key func(map[string]any) string) []any {
		list := append([]any(nil), items.([]any)...)
		sort.SliceStable(list, func(i, j int) bool { return key(list[i].(map[string]any)) < key(list[j].(map[string]any)) })
		return list
	}
	str := func(m map[string]any, k string) string { s, _ := m[k].(string); return s }
	sessions := sortedBy(report["sessions"], func(m map[string]any) string { return str(m, "cli") + "|" + str(m, "id") })
	for _, s := range sessions {
		m := s.(map[string]any)
		// The Node oracle predates birth-bound Codex ids; ActivitySafetyTests holds the real ids.
		if str(m, "cli") == "codex" && strings.HasPrefix(str(m, "id"), "pid:") {
			m["id"] = "pid:" + m["pid"].(json.Number).String()
		}
	}
	stats := report["stats"].(map[string]any)
	return map[string]any{
		"sessions":     sessions,
		"failures":     sortedBy(report["failures"], func(m map[string]any) string { return str(m, "cli") + "|" + str(m, "kind") + "|" + str(m, "key") }),
		"files":        sortedBy(report["files"], func(m map[string]any) string { return str(m, "path") }),
		"unmeasurable": report["unmeasurable"],
		"stats":        map[string]any{"logs": stats["logs"], "truncated": stats["truncated"]},
	}
}

// encodeReport is the report as the protocol encodes it, read back as a generic tree. A non-empty root is replaced
// by $HOME in the encoded text (the home-token projection). goldentest.HomeToken is not used here: it returns a
// json.Number as a plain string, which would hide a number-versus-string mismatch and skip Canonical's number writer.
func encodeReport(t *testing.T, report Report, root string) map[string]any {
	t.Helper()
	data, err := json.Marshal(report)
	if err != nil {
		t.Fatal(err)
	}
	if root != "" {
		data = bytes.ReplaceAll(data, []byte(root), []byte(goldentest.Token))
	}
	return decode(t, data).(map[string]any)
}

func goldenSection(t *testing.T, name, section string) map[string]any {
	t.Helper()
	g, err := goldentest.LoadGolden(name)
	if err != nil {
		t.Fatal(err)
	}
	return g.(map[string]any)[section].(map[string]any)
}

// fixtureProc builds the fake process list from a section of activity-proc.json.
func fixtureProc(t *testing.T, section string) *proc.Fixture {
	t.Helper()
	spec := goldenSection(t, "activity-proc", section)
	var alive []int
	for _, v := range spec["alive"].([]any) {
		n, _ := v.(json.Number).Int64()
		alive = append(alive, int(n))
	}
	starts := map[int]string{}
	for k, v := range spec["starts"].(map[string]any) {
		pid, err := strconv.Atoi(k)
		if err != nil {
			t.Fatal(err)
		}
		starts[pid] = v.(string)
	}
	var threads []proc.Thread
	for _, v := range spec["threads"].([]any) {
		m := v.(map[string]any)
		n, _ := m["pid"].(json.Number).Int64()
		id, _ := m["threadId"].(string) // null is the Swift nil: a process with no thread yet
		threads = append(threads, proc.Thread{Pid: int(n), ThreadID: id})
	}
	return proc.NewFixture(alive, starts, threads, 0)
}

func goldenOptions() Options {
	o := DefaultOptions()
	o.MaxHistoryFiles = 100_000 // the golden script lifts the cap so directory order cannot decide which logs are read
	return o
}

func countCases(section map[string]any) int {
	return len(section["sessions"].([]any)) + len(section["failures"].([]any)) + len(section["files"].([]any))
}

func assertNow(t *testing.T) {
	t.Helper()
	g, err := goldentest.LoadGolden("activity")
	if err != nil {
		t.Fatal(err)
	}
	if got := g.(map[string]any)["now"].(json.Number).String(); got != strconv.FormatInt(int64(activityNowMs), 10) {
		t.Fatalf("golden now = %s", got)
	}
	now, err := goldentest.Now()
	if err != nil || !now.Equal(activityNow) {
		t.Fatalf("manifest now = %v (%v)", now, err)
	}
}

func TestGoldenActivityShared(t *testing.T) { // Swift: ActivityGoldenTests.swift "shared fixture HOME: sessions, failures and files match the Node report"
	if runtime.GOOS != "darwin" {
		t.Skip("the canonical fixture root is a macOS path (B6)")
	}
	assertNow(t)
	root, err := goldentest.Materialize()
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := config.LoadFrom(func(k string) string { return goldentest.Env(root)[k] })
	if err != nil {
		t.Fatal(err)
	}
	realHome, _ := roots.RealHome()
	r, err := roots.Resolve(cfg, realHome)
	if err != nil {
		t.Fatal(err)
	}
	report, err := NewEngine().Read(context.Background(), r, activityNow, fixtureProc(t, "shared"), goldenOptions())
	if err != nil {
		t.Fatal(err)
	}
	want := goldenSection(t, "activity", "shared")
	goldentest.AssertCaseCount(t, "activity shared", countCases(want), 16)
	goldentest.AssertCanonicalEqual(t, "activity shared", oracleProjection(want), oracleProjection(encodeReport(t, report, root)))

	// the shared tree must keep covering the cases it was written for
	has := func(pred func(Session) bool) bool {
		for _, s := range report.Sessions {
			if pred(s) {
				return true
			}
		}
		return false
	}
	if !has(func(s Session) bool { return s.State == StateRunning && s.CLI == CLIClaude }) {
		t.Error("no running Claude session")
	}
	if !has(func(s Session) bool { return s.State == StateWaiting }) {
		t.Error("no waiting session")
	}
	if !has(func(s Session) bool { return s.ReasonCode != nil && *s.ReasonCode == ReasonCodexToolSilent }) {
		t.Error("no codex-tool-silent session")
	}
	if !has(func(s Session) bool { return s.ReasonCode != nil && *s.ReasonCode == ReasonCodexNoRollout }) {
		t.Error("no codex-no-rollout session")
	}
	if _, ok := findFailure(report, func(f Failure) bool { return f.Count == 8 && f.LaterPass != nil }); !ok {
		t.Error("no failure with count 8 and a later pass")
	}
}

// copyActivityHome writes the files listed in activity-home/mtimes.json into the sandbox, keeping their mtimes.
// keep selects which files to copy.
func copyActivityHome(t *testing.T, sb *sandbox, keep func(rel string) bool) {
	t.Helper()
	dir, err := goldentest.FixturesDir()
	if err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(dir, "activity-home")
	data, err := os.ReadFile(filepath.Join(source, "mtimes.json"))
	if err != nil {
		t.Fatal(err)
	}
	var m struct {
		Mtimes map[string]float64 `json:"mtimes"`
	}
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	if len(m.Mtimes) == 0 {
		t.Fatal("mtimes.json lists no files")
	}
	for rel, ms := range m.Mtimes {
		if !keep(rel) {
			continue
		}
		content, err := os.ReadFile(filepath.Join(source, rel))
		if err != nil {
			t.Fatal(err)
		}
		sb.setMtime(sb.write(rel, content), ms)
	}
}

func TestGoldenActivityExtra(t *testing.T) { // Swift: "section fixture HOME: ended, unknown, unpriced, compressed, child, hook and legacy cases match the Node report"
	assertNow(t)
	sb := newSandbox(t)
	copyActivityHome(t, sb, func(string) bool { return true })
	report := sb.readWith(fixtureProc(t, "extra"), goldenOptions())
	want := goldenSection(t, "activity", "extra")
	goldentest.AssertCaseCount(t, "activity extra", countCases(want), 36)
	goldentest.AssertCanonicalEqual(t, "activity extra", oracleProjection(want), oracleProjection(encodeReport(t, report, "")))

	has := func(pred func(Session) bool) bool {
		for _, s := range report.Sessions {
			if pred(s) {
				return true
			}
		}
		return false
	}
	if !has(func(s Session) bool { return s.State == StateEnded }) {
		t.Error("no ended session")
	}
	if !has(func(s Session) bool { return s.ReasonCode != nil && *s.ReasonCode == ReasonClaudeUnknownStatus }) {
		t.Error("no unknown-status session")
	}
	if !has(func(s Session) bool {
		return s.Cost == nil && s.CostNote != nil && strings.HasPrefix(*s.CostNote, "No price for model")
	}) {
		t.Error("no unpriced session")
	}
	if _, ok := findFailure(report, func(f Failure) bool { return f.Kind == KindHook }); !ok {
		t.Error("no hook failure")
	}
	// R4: the recorded `touch` command is listed as a failure and was never run
	if _, ok := findFailure(report, func(f Failure) bool { return strings.HasPrefix(f.Title, "touch /nonexistent-reins-marker/") }); !ok {
		t.Error("the touch command is not listed")
	}
	if _, err := os.Stat("/nonexistent-reins-marker/must-not-exist"); err == nil {
		t.Error("the recorded command was run")
	}
}

func TestCompressedRollouts(t *testing.T) { // Swift: "a compressed rollout is read once, and a tail cut is reported"
	sb := newSandbox(t)
	copyActivityHome(t, sb, func(rel string) bool {
		return strings.HasSuffix(rel, ".jsonl.zst") || rel == ".codex/session_index.jsonl"
	})
	engine := NewEngine()
	p := newFakeProc(nil, nil, []proc.Thread{{Pid: 4049, ThreadID: activityUUID(49)}, {Pid: 4050, ThreadID: activityUUID(50)}})
	read := func(e *Engine, opts Options) Report {
		r, err := e.Read(context.Background(), sb.roots, activityNow, p, opts)
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	first := read(engine, goldenOptions())
	build, ok := findFailure(first, func(f Failure) bool { return f.Title == "npm run build" })
	if !ok || build.Count != 2 {
		t.Fatalf("npm run build = %+v (found %v)", build, ok)
	}
	found := false
	for _, f := range first.Files {
		found = found || f.Path == "/work/app-a/src/rank.ts"
	}
	if !found {
		t.Error("the compressed rollout's edit is missing")
	}
	eq(t, "49 state", mustSession(t, first, activityUUID(49)).State, StateRunning)
	if sessionByID(first, activityUUID(50)) != nil {
		t.Error("a compressed child rollout is not a session")
	}
	statesBefore := map[*logState]int{}
	for _, e := range engine.cache {
		statesBefore[e.state] = len(e.state.failures) + len(e.state.edits) + len(e.state.passes)
	}
	second := read(engine, goldenOptions())
	if !equalReports(second, first) {
		t.Error("a second read must not fold the same lines again")
	}
	for _, e := range engine.cache {
		before, same := statesBefore[e.state]
		if !same {
			t.Error("a second read replaced a folded state: a compressed log was read again")
		} else if before != len(e.state.failures)+len(e.state.edits)+len(e.state.passes) {
			t.Error("a second read folded lines again")
		}
	}

	cut := goldenOptions()
	cut.HistoryTailBytes, cut.LiveTailBytes = 300, 300
	small := read(NewEngine(), cut)
	if small.Stats.Truncated < 1 {
		t.Errorf("stats.truncated = %d, want >= 1", small.Stats.Truncated)
	}
	if mustSession(t, small, activityUUID(49)).Cost != nil {
		t.Error("a cut log gives no cost estimate")
	}
}

func equalReports(a, b Report) bool {
	ja, _ := json.Marshal(a)
	jb, _ := json.Marshal(b)
	return bytes.Equal(ja, jb)
}
