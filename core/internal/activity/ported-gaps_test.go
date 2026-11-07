package activity

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// Two Swift tests the coverage ledger found without a Go port.

// guardedProc is the real system adapter for IsAlive and Identify, so its pid guard is what decides, but Terminate
// only records: a guard that regressed must fail this test, not signal pid 0 (a process group) or -1 (everything).
type guardedProc struct {
	proc.System
	mu         sync.Mutex
	terminated []int
}

func (g *guardedProc) Terminate(_ context.Context, pid int) error {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.terminated = append(g.terminated, pid)
	return nil
}

func TestStopIgnoresUnsafePidInStatusFile(t *testing.T) { // Swift: ProcessGuardTests.swift "stopSession with a status file that carries pid 0 or -1 finds no live session and signals nothing"
	if !proc.NewSystem().Measurable() {
		t.Skip("the system adapter cannot measure processes on this OS")
	}
	for _, c := range []struct {
		file string
		pid  int
	}{{"0.json", 0}, {"1.json", -1}} {
		sb := newSandbox(t)
		id := activityUUID(10)
		sb.put(".claude/sessions/"+c.file, `{"pid": `+strconv.Itoa(c.pid)+`, "sessionId": "`+id+`", "procStart": "Mon Nov  2 11:00:00 2026", "status": "idle"}`, 0)
		g := &guardedProc{}
		_, err := Stop(context.Background(), sb.roots, CLIClaude, id, g, fastStop)
		if err == nil {
			t.Errorf("pid %d: Stop returned without an error", c.pid)
		} else if got := stopStatusOf(err); got != 404 {
			t.Errorf("pid %d: status %d, want 404", c.pid, got)
		}
		if len(g.terminated) != 0 {
			t.Errorf("pid %d: Terminate called with %v", c.pid, g.terminated)
		}
	}
}

func TestSymlinkedClaudeRootKeepsStateAndTool(t *testing.T) { // Swift: ReadHardeningTests.swift "a symlinked Claude root still gives its sessions a state and a tool"
	sb := newSandbox(t)
	real := filepath.Join(sb.home, "dotfiles", "claude")
	if err := os.MkdirAll(real, 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(sb.home, "linked-claude")
	if err := os.Symlink(real, link); err != nil {
		t.Skipf("cannot create a symlink here: %v", err)
	}
	sid := activitySid(1)
	c := claudeRecords{cwd: "/work/app", session: sid}
	records := []obj{c.user("Build it", activityMinutes(1)), c.tool("b1", "Bash", obj{"command": "sleep 1"}, activityNowMs-50_000)}
	sb.put("dotfiles/claude/projects/-work-app/"+sid+".jsonl", jsonLines(records), 1000)
	sb.put("dotfiles/claude/sessions/1.json", activityJSON(obj{
		"pid": 1, "sessionId": sid, "cwd": "/work/app", "startedAt": activityNowMs - 3_600_000,
		"procStart": "Mon Nov  2 11:00:00 2026", "status": "busy", "name": "app-1", "nameSource": "derived", "statusUpdatedAt": activityNowMs - 3_000_000,
	}), 0)

	cfg, err := config.LoadFrom(func(k string) string {
		return map[string]string{"HOME": sb.home, "CLAUDE_CONFIG_DIR": link, "CODEX_HOME": sb.home + "/.codex", "SPACEVIBE_HOME": sb.home + "/.spacevibe", "SPACEVIBE_TEST": "1"}[k]
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
	sb.roots = r
	report := sb.read(newFakeProc([]int{1}, map[int]string{1: "Mon Nov  2 11:00:00 2026"}, nil))
	found := sessionByID(report, sid)
	if found == nil {
		t.Fatalf("no session %s under the symlinked root; sessions: %d", sid, len(report.Sessions))
	}
	eq(t, "state", found.State, StateRunning)
	if found.CurrentTool == nil {
		t.Fatal("no current tool")
	}
	eq(t, "tool", found.CurrentTool.Name, "Bash")
}
