//go:build darwin

package proc

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestSystemListsCurrentProcess(t *testing.T) {
	a := NewSystem()
	pid := os.Getpid()
	if !a.Measurable() || !a.IsAlive(ctx, pid) {
		t.Fatal("the test process must be alive")
	}
	start, ok := a.StartTime(ctx, pid)
	if !ok {
		t.Fatal("no start time for the test process")
	}
	// The ps lstart text, UTC, as Claude writes procStart: "Mon Nov  2 11:58:00 2026".
	started, err := time.Parse("Mon Jan _2 15:04:05 2006", start)
	if err != nil {
		t.Fatalf("lstart %q: %v", start, err)
	}
	if d := time.Since(started); d < -2*time.Second || d > time.Hour {
		t.Fatalf("start %q is %v ago, not near now (TZ=UTC not applied?)", start, d)
	}
	res, ok := run(ctx, psPath, []string{"-axo", "pid=,args="}, listTimeout)
	if !ok || res.status != 0 || !strings.Contains(res.stdout, strconv.Itoa(pid)+" ") {
		t.Fatalf("ps did not list pid %d (ok=%v status=%d)", pid, ok, res.status)
	}
	// Whatever codex processes this machine has, the call must not fail and every entry must have a valid pid.
	for _, th := range a.CodexThreads(ctx) {
		if th.Pid <= 0 {
			t.Fatalf("thread with pid %d", th.Pid)
		}
	}
}

func TestRunSetsEnvironment(t *testing.T) {
	res, ok := run(ctx, "/usr/bin/env", nil, startTimeout)
	if !ok || res.status != 0 {
		t.Fatal("env did not run")
	}
	for _, want := range []string{"TZ=UTC", "LC_ALL=C"} {
		if !strings.Contains("\n"+res.stdout, "\n"+want+"\n") {
			t.Errorf("environment lacks %s", want)
		}
	}
}

func TestRunKillsOnTimeout(t *testing.T) {
	t0 := time.Now()
	res, ok := run(ctx, "/bin/sleep", []string{"30"}, 150*time.Millisecond)
	if !ok {
		t.Fatal("sleep did not start")
	}
	if d := time.Since(t0); d > 5*time.Second {
		t.Fatalf("a timed-out tool was waited for %v", d)
	}
	if res.status == 0 {
		t.Fatal("a killed tool must not report success")
	}
}

func TestRunMissingTool(t *testing.T) {
	if _, ok := run(ctx, "/nonexistent/tool", nil, time.Second); ok {
		t.Fatal("a tool that cannot start must report ok=false")
	}
}

// Swift: ActivityStopTests.swift "the real adapter ends a child process this test spawned, matched by its real start time"
// (adapter half; stopSession itself belongs to the activity port).
func TestSystemEndsSpawnedChild(t *testing.T) {
	child := exec.Command("/bin/sleep", "30")
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = child.Process.Kill() }()
	a := NewSystem()
	pid := child.Process.Pid
	if _, ok := a.StartTime(ctx, pid); !ok || !a.IsAlive(ctx, pid) {
		t.Fatal("the child must be alive with a start time")
	}
	if err := a.Terminate(ctx, pid); err != nil {
		t.Fatal(err)
	}
	_ = child.Wait()
	ws, ok := child.ProcessState.Sys().(syscall.WaitStatus)
	if !ok || !ws.Signaled() || ws.Signal() != syscall.SIGTERM {
		t.Fatalf("child state %v, want killed by SIGTERM", child.ProcessState)
	}
	if a.IsAlive(ctx, pid) {
		t.Fatal("a reaped child must not be alive")
	}
	if err := a.Terminate(ctx, pid); !errors.Is(err, ErrNoSuchProcess) {
		t.Fatalf("terminate after exit = %v, want ErrNoSuchProcess (ESRCH)", err)
	}
}

// launchd (pid 1) belongs to root, so a normal user gets EPERM, and IsAlive counts EPERM as alive.
func TestSystemMapsEPERM(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root may signal pid 1")
	}
	a := NewSystem()
	if !a.IsAlive(context.Background(), 1) {
		t.Error("pid 1 must count as alive (EPERM)")
	}
	if err := a.Terminate(context.Background(), 1); !errors.Is(err, ErrNotPermitted) {
		t.Fatalf("terminate pid 1 = %v, want ErrNotPermitted", err)
	}
}
