package activity

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// Helpers shared by the Activity tests, ported from the top of ActivityTests.swift. Every log, status file and lock
// is generated inside a temporary HOME (SPACEVIBE_TEST=1 makes roots refuse the real home); ps, lsof and kill are
// replaced by fakeProc. Nothing here reads the real ~/.claude or ~/.codex.

const activityNowMs = 1_793_620_800_000.0 // 2026-11-02T12:00:00Z

var activityNow = time.UnixMilli(int64(activityNowMs))

type obj = map[string]any

func activityIso(ms float64) string { return isoOf(ms) }

func activityMinutes(minutes float64) float64 { return activityNowMs - minutes*60_000 }

func activityUUID(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012d", n) }

func activitySid(n int) string {
	s := fmt.Sprint(n)
	return strings.Repeat("a", max(0, 8-len(s))) + s + "-0000-4000-8000-000000000000"
}

// activityJSON is sorted keys, no HTML escaping, no trailing newline.
func activityJSON(v any) string {
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		panic(err)
	}
	return strings.TrimSuffix(b.String(), "\n")
}

func jsonLines(records []obj) string {
	var parts []string
	for _, r := range records {
		parts = append(parts, activityJSON(r))
	}
	return strings.Join(parts, "\n") + "\n"
}

// fakeProc replays a fixed process list and records what it was asked to terminate.
type fakeProc struct {
	mu             sync.Mutex
	alive          map[int]bool
	starts         map[int]string
	threads        []proc.Thread
	killed         []int
	terminateError error
	ignoresSignal  bool
	// threadsError makes CodexThreads fail (ps unknown); identifyErrors makes Identify fail per pid;
	// laterStarts replaces a pid's start from its second Identify on (a pid reused between lookup and kill);
	// names gives a pid its executable name (default "proc"), laterNames the name from the second Identify on.
	threadsError   error
	identifyErrors map[int]error
	laterStarts    map[int]string
	names          map[int]string
	laterNames     map[int]string
	laterErrors    map[int]error // Identify error from the second call on
	identifyCalls  map[int]int
	notMeasurable  bool
}

func newFakeProc(alive []int, starts map[int]string, threads []proc.Thread) *fakeProc {
	f := &fakeProc{alive: map[int]bool{}, starts: starts, threads: threads}
	for _, pid := range alive {
		f.alive[pid] = true
	}
	return f
}

func (f *fakeProc) Measurable() bool { return !f.notMeasurable }
func (f *fakeProc) IsAlive(_ context.Context, pid int) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.alive[pid]
}
func (f *fakeProc) StartTime(_ context.Context, pid int) (string, bool) {
	s, ok := f.starts[pid]
	return s, ok
}
func (f *fakeProc) CodexThreads(context.Context) ([]proc.Thread, error) {
	if f.threadsError != nil {
		return nil, f.threadsError
	}
	return f.threads, nil
}

// Identify is the pid's start (from the starts map; none is ErrUnknown, as a ps that printed nothing useful) and name.
func (f *fakeProc) Identify(_ context.Context, pid int) (proc.Identity, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if err := f.identifyErrors[pid]; err != nil {
		return proc.Identity{}, err
	}
	known := f.alive[pid]
	for _, t := range f.threads {
		known = known || t.Pid == pid
	}
	if !known {
		return proc.Identity{}, proc.ErrNoSuchProcess
	}
	if f.identifyCalls == nil {
		f.identifyCalls = map[int]int{}
	}
	f.identifyCalls[pid]++
	later := f.identifyCalls[pid] > 1
	if err := f.laterErrors[pid]; later && err != nil {
		return proc.Identity{}, err
	}
	start, ok := f.starts[pid]
	if s, has := f.laterStarts[pid]; later && has {
		start, ok = s, true
	}
	if !ok {
		return proc.Identity{}, proc.ErrUnknown
	}
	name := "proc"
	if n, has := f.names[pid]; has {
		name = n
	}
	if n, has := f.laterNames[pid]; later && has {
		name = n
	}
	return proc.Identity{Start: start, Name: name}, nil
}
func (f *fakeProc) Terminate(_ context.Context, pid int) error {
	if f.terminateError != nil {
		return f.terminateError
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.killed = append(f.killed, pid)
	if !f.ignoresSignal {
		delete(f.alive, pid)
	}
	return nil
}
func (f *fakeProc) killedPids() []int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]int(nil), f.killed...)
}

// claudeRecords builds Claude Code transcript lines.
type claudeRecords struct{ cwd, session string }

func (c claudeRecords) user(text string, at float64) obj {
	return obj{"type": "user", "timestamp": activityIso(at), "cwd": c.cwd, "sessionId": c.session, "message": obj{"role": "user", "content": text}}
}

func (c claudeRecords) tool(id, name string, input obj, at float64) obj {
	return c.toolWith(id, name, input, at, "claude-sonnet-4-6", nil, "")
}

func (c claudeRecords) toolWith(id, name string, input obj, at float64, model string, usage obj, messageID string) obj {
	if messageID == "" {
		messageID = "msg-" + id
	}
	message := obj{"id": messageID, "model": model, "content": []any{obj{"type": "tool_use", "id": id, "name": name, "input": input}}}
	if usage != nil {
		message["usage"] = usage
	}
	return obj{"type": "assistant", "timestamp": activityIso(at), "cwd": c.cwd, "sessionId": c.session, "message": message}
}

func (c claudeRecords) result(id, text string, isError bool, at float64) obj {
	return obj{"type": "user", "timestamp": activityIso(at), "cwd": c.cwd, "sessionId": c.session,
		"message": obj{"role": "user", "content": []any{obj{"type": "tool_result", "tool_use_id": id, "is_error": isError, "content": text}}}}
}

func (c claudeRecords) hookFail(n int, event, command string, at float64) obj {
	return obj{"type": "attachment", "uuid": activityUUID(n), "timestamp": activityIso(at), "cwd": c.cwd, "sessionId": c.session,
		"attachment": obj{"type": "hook_non_blocking_error", "hookEvent": event, "hookName": event, "command": command, "exitCode": 1, "stderr": "check failed\nsecond line", "toolUseID": fmt.Sprintf("tu-%d", n)}}
}

// codexRecords builds Codex rollout lines.
type codexRecords struct{ id string }

func (c codexRecords) rec(at float64, kind string, payload obj) obj {
	return obj{"timestamp": activityIso(at), "type": kind, "payload": payload}
}

func (c codexRecords) meta(at float64, cwd string, extra obj) obj {
	payload := obj{"id": c.id, "cwd": cwd, "timestamp": activityIso(at), "source": "cli"}
	for k, v := range extra {
		payload[k] = v
	}
	return c.rec(at, "session_meta", payload)
}
func (c codexRecords) model(at float64, model string) obj {
	return c.rec(at, "turn_context", obj{"model": model})
}
func (c codexRecords) started(at float64) obj {
	return c.rec(at, "event_msg", obj{"type": "task_started", "turn_id": "t"})
}
func (c codexRecords) done(at float64) obj {
	return c.rec(at, "event_msg", obj{"type": "task_complete", "turn_id": "t"})
}
func (c codexRecords) aborted(at float64) obj {
	return c.rec(at, "event_msg", obj{"type": "turn_aborted", "turn_id": "t"})
}
func (c codexRecords) say(at float64, text string) obj {
	return c.rec(at, "event_msg", obj{"type": "item_completed", "item": obj{"type": "UserMessage", "id": fmt.Sprintf("u%d", int(at)), "content": []any{obj{"type": "text", "text": text}}}})
}
func (c codexRecords) call(at float64, callID, name string, args obj) obj {
	return c.rec(at, "response_item", obj{"type": "function_call", "call_id": callID, "name": name, "arguments": activityJSON(args)})
}
func (c codexRecords) exec(at float64, n int, command string, exit int, output string) obj {
	return c.rec(at, "event_msg", obj{"type": "item_completed", "item": obj{"type": "CommandExecution", "id": fmt.Sprintf("ce%d", n), "command": []any{"/bin/zsh", "-lc", command}, "cwd": "/work", "exit_code": exit, "aggregated_output": output}})
}
func (c codexRecords) patch(at float64, n int, paths []string, status string) obj {
	changes := obj{}
	for _, p := range paths {
		changes[p] = obj{"type": "update", "unified_diff": ""}
	}
	return c.rec(at, "event_msg", obj{"type": "item_completed", "item": obj{"type": "FileChange", "id": fmt.Sprintf("fc%d", n), "status": status, "changes": changes}})
}
func (c codexRecords) tokens(at float64, input, cached, output int) obj {
	return c.rec(at, "event_msg", obj{"type": "token_count", "info": obj{"total_token_usage": obj{"input_tokens": input, "cached_input_tokens": cached, "output_tokens": output}}})
}

// sandbox is a temporary HOME with helpers that write logs and status files whose mtimes are now - ageMs.
type sandbox struct {
	t     *testing.T
	home  string
	roots roots.Roots
}

func newSandbox(t *testing.T) *sandbox {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := config.LoadFrom(func(k string) string {
		return map[string]string{
			"HOME": dir, "CLAUDE_CONFIG_DIR": dir + "/.claude", "CODEX_HOME": dir + "/.codex", "SPACEVIBE_HOME": dir + "/.spacevibe", "SPACEVIBE_TEST": "1",
		}[k]
	})
	if err != nil {
		t.Fatal(err)
	}
	realHome, err := roots.RealHome()
	if err != nil {
		t.Fatal(err)
	}
	r, err := roots.Resolve(cfg, realHome)
	if err != nil {
		t.Fatal(err)
	}
	return &sandbox{t: t, home: dir, roots: r}
}

func (s *sandbox) write(rel string, data []byte) string {
	s.t.Helper()
	path := filepath.Join(s.home, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		s.t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		s.t.Fatal(err)
	}
	return path
}

func (s *sandbox) setMtime(path string, ms float64) {
	s.t.Helper()
	at := time.UnixMilli(int64(ms))
	if err := os.Chtimes(path, at, at); err != nil {
		s.t.Fatal(err)
	}
}

func (s *sandbox) put(rel, text string, ageMs float64) string {
	s.t.Helper()
	path := s.write(rel, []byte(text))
	s.setMtime(path, activityNowMs-ageMs)
	return path
}

func (s *sandbox) claudeLog(cwd, session string, records []obj, ageMs float64) string {
	folder := strings.NewReplacer("/", "-", ".", "-").Replace(cwd)
	return s.put(fmt.Sprintf(".claude/projects/%s/%s.jsonl", folder, session), jsonLines(records), ageMs)
}

// status writes a Claude status file; over replaces the defaults.
func (s *sandbox) status(pid int, over obj) {
	s.t.Helper()
	st := obj{
		"pid": pid, "sessionId": activitySid(pid), "cwd": "/work/app", "startedAt": activityNowMs - 3_600_000,
		"procStart": "Mon Nov  2 11:00:00 2026", "status": "idle", "name": "app-1", "nameSource": "derived", "statusUpdatedAt": activityNowMs - 3_000_000,
	}
	for k, v := range over {
		st[k] = v
	}
	s.put(fmt.Sprintf(".claude/sessions/%d.json", pid), activityJSON(st), 0)
}

func (s *sandbox) codexLog(id string, records []obj, ageMs float64) string {
	return s.put(fmt.Sprintf(".codex/sessions/2026/11/02/rollout-2026-11-02T01-00-00-%s.jsonl", id), jsonLines(records), ageMs)
}

func (s *sandbox) read(p proc.Adapter) Report { return s.readWith(p, DefaultOptions()) }

func (s *sandbox) readWith(p proc.Adapter, opts Options) Report {
	s.t.Helper()
	report, err := NewEngine().Read(context.Background(), s.roots, activityNow, p, opts)
	if err != nil {
		s.t.Fatal(err)
	}
	return report
}

func sessionByID(report Report, id string) *Session {
	for i := range report.Sessions {
		if report.Sessions[i].ID == id {
			return &report.Sessions[i]
		}
	}
	return nil
}

func isoOf(ms float64) string { return *isoOrNil(ms) }
