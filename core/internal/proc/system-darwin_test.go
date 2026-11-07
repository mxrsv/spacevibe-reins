//go:build darwin

package proc

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
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
	threads, err := a.CodexThreads(ctx)
	if err != nil {
		t.Fatalf("CodexThreads: %v", err)
	}
	for _, th := range threads {
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

// script writes an executable stand-in for ps or lsof.
func script(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "tool")
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"+body+"\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestSystemIdentify(t *testing.T) {
	a := NewSystem()
	id, err := a.Identify(ctx, os.Getpid())
	if err != nil || id.Start == "" || id.Name == "" {
		t.Fatalf("Identify(self) = %+v, %v", id, err)
	}
	if start, _ := a.StartTime(ctx, os.Getpid()); strings.Join(strings.Fields(start), " ") != id.Start {
		t.Errorf("Identify start %q differs from StartTime %q", id.Start, start)
	}
	child := exec.Command("/bin/sleep", "30")
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	cid, err := a.Identify(ctx, child.Process.Pid)
	if err != nil || cid.Name != "sleep" {
		t.Errorf("Identify(sleep child) = %+v, %v", cid, err)
	}
	_ = child.Process.Kill()
	_ = child.Wait()
	if _, err := a.Identify(ctx, child.Process.Pid); !errors.Is(err, ErrNoSuchProcess) {
		t.Errorf("a reaped child is ErrNoSuchProcess, got %v", err)
	}
}

// G-fix.10: a ps that fails is "unknown", never "no such process".
func TestSystemIdentifyPsFailureIsUnknown(t *testing.T) {
	for name, body := range map[string]string{
		"exit 2":         "exit 2",
		"exit 0, silent": "exit 0",
		"unparsable":     "echo garbage",
		"killed":         "kill -9 $$",
	} {
		a := System{ps: script(t, body)}
		if _, err := a.Identify(ctx, 4242); !errors.Is(err, ErrUnknown) {
			t.Errorf("%s: Identify = %v, want ErrUnknown", name, err)
		}
	}
	if _, err := (System{ps: "/nonexistent/ps"}).Identify(ctx, 4242); !errors.Is(err, ErrUnknown) {
		t.Errorf("missing ps: %v", err)
	}
	// ps exit 1 with no output is how ps reports a pid that is not there.
	if _, err := (System{ps: script(t, "exit 1")}).Identify(ctx, 4242); !errors.Is(err, ErrNoSuchProcess) {
		t.Errorf("absent pid: %v", err)
	}
	tctx, cancel := context.WithTimeout(ctx, 100*time.Millisecond)
	defer cancel()
	if _, err := (System{ps: script(t, "sleep 5")}).Identify(tctx, 4242); !errors.Is(err, ErrUnknown) {
		t.Errorf("ps timeout: %v", err)
	}
}

// psListing prints one codex process, as `ps -axo pid=,args=` would.
const psListing = `echo "  900 /usr/local/bin/codex"`

func TestCodexThreadsPsFailureIsUnknown(t *testing.T) {
	for name, a := range map[string]System{
		"ps exit 2":  {ps: script(t, "exit 2")},
		"ps missing": {ps: "/nonexistent/ps"},
		"ps timeout": {ps: script(t, "sleep 5")},
		"ps SIGKILL": {ps: script(t, "kill -9 $$")},
	} {
		tctx, cancel := context.WithTimeout(ctx, 200*time.Millisecond)
		got, err := a.CodexThreads(tctx)
		cancel()
		if !errors.Is(err, ErrUnknown) || got != nil {
			t.Errorf("%s: %v, %v; want nil and ErrUnknown", name, got, err)
		}
	}
}

func TestCodexThreadsLsofFailureMarksLocksUnknown(t *testing.T) {
	ps := script(t, psListing)
	want := []Thread{{Pid: 900, LockUnknown: true}}
	for name, lsof := range map[string]string{
		"exit 2":        script(t, "exit 2"),
		"missing":       "/nonexistent/lsof",
		"timeout":       script(t, "sleep 5"),
		"empty, exit 1": script(t, "exit 1"),
		"killed":        script(t, "echo p900; kill -9 $$"),
	} {
		tctx, cancel := context.WithTimeout(ctx, 300*time.Millisecond)
		got, err := (System{ps: ps, lsof: lsof}).CodexThreads(tctx)
		cancel()
		if err != nil || !reflect.DeepEqual(got, want) {
			t.Errorf("%s: %v, %v; want %v", name, got, err, want)
		}
	}
}

func TestCodexThreadsLsofSuccess(t *testing.T) {
	lock := "/h/.codex/thread-writer-locks/a0000000-0000-4000-8000-000000000001.lock"
	// exit 1 with output: lsof's normal answer when another pid had already exited.
	a := System{ps: script(t, psListing), lsof: script(t, "printf 'p900\\nn"+lock+"\\n'; exit 1")}
	got, err := a.CodexThreads(ctx)
	if err != nil || !reflect.DeepEqual(got, []Thread{{Pid: 900, ThreadID: "a0000000-0000-4000-8000-000000000001"}}) {
		t.Errorf("got %v, %v", got, err)
	}
	// No codex process at all: a real, empty answer.
	a = System{ps: script(t, "echo '  1 /sbin/launchd'")}
	if got, err := a.CodexThreads(ctx); err != nil || len(got) != 0 {
		t.Errorf("no codex: %v, %v", got, err)
	}
}
