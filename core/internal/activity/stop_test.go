package activity

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os/exec"
	"runtime"
	"syscall"
	"testing"
	"time"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/proc"
)

// Ported from Tests/ReinsCoreTests/ActivityStopTests.swift and ActivitySafetyTests.swift. stop goes through a fake
// adapter: nothing is signalled for real, and the pid always comes from the live system.

const (
	stopStart        = "Mon Nov  2 11:00:00 2026"
	replacementStart = "Mon Nov  2 11:01:00 2026"
)

var fastStop = StopOptions{Wait: 30 * time.Millisecond, Poll: 5 * time.Millisecond}

func stopStatusOf(err error) int {
	if e, ok := coreerr.As(err); ok {
		return e.Status
	}
	return 0
}

func stopSession(t *testing.T, sb *sandbox, cli CLI, id string, p *fakeProc, opts StopOptions) (StopResult, error) {
	t.Helper()
	return Stop(context.Background(), sb.roots, cli, id, p, opts)
}

func expectRefusal(t *testing.T, sb *sandbox, cli CLI, id string, p *fakeProc, opts StopOptions) {
	t.Helper()
	_, err := stopSession(t, sb, cli, id, p, opts)
	if err == nil {
		t.Errorf("%s %s: an unverified process identity must not authorize Stop", cli, id)
	} else if stopStatusOf(err) != 404 {
		t.Errorf("%s %s: status %d, want 404", cli, id, stopStatusOf(err))
	}
	if len(p.killedPids()) != 0 {
		t.Errorf("%s %s: signalled %v", cli, id, p.killedPids())
	}
}

func TestStopClaude(t *testing.T) { // Swift: ActivityStopTests "signals the Claude process that the status file names, and reports that it exited"
	sb := newSandbox(t)
	sb.status(11, obj{"procStart": stopStart})
	p := newFakeProc([]int{11}, map[int]string{11: "Mon Nov  2  11:00:00  2026"}, nil)
	result, err := stopSession(t, sb, CLIClaude, activitySid(11), p, fastStop)
	if err != nil || result != (StopResult{Exited: true}) {
		t.Fatalf("result = %+v, err = %v", result, err)
	}
	if got := p.killedPids(); len(got) != 1 || got[0] != 11 {
		t.Errorf("killed = %v", got)
	}
}

func TestStopRefuses(t *testing.T) { // Swift: ActivityStopTests "refuses a reused pid, a dead process and an unknown session, and signals nothing"
	sb := newSandbox(t)
	sb.status(12, obj{"procStart": stopStart})
	sb.status(13, obj{"procStart": stopStart})
	for i, c := range []struct {
		cli CLI
		id  string
		p   *fakeProc
	}{
		{CLIClaude, activitySid(12), newFakeProc([]int{12}, map[int]string{12: "Tue Nov  3 01:00:00 2026"}, nil)}, // pid reused
		{CLIClaude, activitySid(12), newFakeProc([]int{12}, nil, nil)},                                            // start time unknown: not proven to be the same process
		{CLIClaude, activitySid(13), newFakeProc(nil, map[int]string{13: stopStart}, nil)},                        // dead
		{CLICodex, activitySid(99), newFakeProc(nil, nil, nil)},
	} {
		t.Run(fmt.Sprint(i), func(t *testing.T) { expectRefusal(t, sb, c.cli, c.id, c.p, fastStop) })
	}
}

func TestStopCodex(t *testing.T) { // Swift: ActivityStopTests "finds a Codex process by its thread lock, or by pid and start identity before the first prompt"
	sb := newSandbox(t)
	threads := []proc.Thread{{Pid: 21, ThreadID: activitySid(21)}, {Pid: 22}}
	byThread := newFakeProc([]int{21, 22}, nil, threads)
	if r, err := stopSession(t, sb, CLICodex, activitySid(21), byThread, fastStop); err != nil || !r.Exited {
		t.Fatalf("by thread: %+v %v", r, err)
	}
	if got := byThread.killedPids(); len(got) != 1 || got[0] != 21 {
		t.Errorf("killed = %v", got)
	}
	byPid := newFakeProc([]int{21, 22}, map[int]string{22: stopStart}, threads)
	id, ok := codexProcessID(22, stopStart, true)
	if !ok {
		t.Fatal("no process id")
	}
	if r, err := stopSession(t, sb, CLICodex, id, byPid, fastStop); err != nil || !r.Exited {
		t.Fatalf("by pid: %+v %v", r, err)
	}
	if got := byPid.killedPids(); len(got) != 1 || got[0] != 22 {
		t.Errorf("killed = %v", got)
	}
	// A pid that holds a thread is not reachable through the bare-pid form.
	expectRefusal(t, sb, CLICodex, "pid:21", newFakeProc([]int{21}, nil, threads), fastStop)
}

func TestStopSignalOutcomes(t *testing.T) { // Swift: ActivityStopTests "says when the process ignored the signal, and turns a permission error into a plain message"
	sb := newSandbox(t)
	sb.status(14, obj{"procStart": stopStart})
	starts := map[int]string{14: stopStart}
	stubborn := newFakeProc([]int{14}, starts, nil)
	stubborn.ignoresSignal = true
	if r, err := stopSession(t, sb, CLIClaude, activitySid(14), stubborn, fastStop); err != nil || r.Exited {
		t.Errorf("stubborn: %+v %v", r, err)
	}
	denied := newFakeProc([]int{14}, starts, nil)
	denied.terminateError = proc.ErrNotPermitted
	_, err := stopSession(t, sb, CLIClaude, activitySid(14), denied, fastStop)
	if stopStatusOf(err) != 403 || err.Error() != "This session belongs to another user, so it cannot be stopped." {
		t.Errorf("denied: %v", err)
	}
	gone := newFakeProc([]int{14}, starts, nil)
	gone.terminateError = proc.ErrNoSuchProcess
	if r, err := stopSession(t, sb, CLIClaude, activitySid(14), gone, fastStop); err != nil || !r.Exited {
		t.Errorf("gone: %+v %v", r, err)
	}
	// Go-only outcomes: any other errno, and an OS where processes cannot be measured, answer 500 with a fixed sentence.
	failed := newFakeProc([]int{14}, starts, nil)
	failed.terminateError = proc.SignalError{Errno: syscall.EINVAL}
	_, err = stopSession(t, sb, CLIClaude, activitySid(14), failed, fastStop)
	if stopStatusOf(err) != 500 || err.Error() != fmt.Sprintf("The session could not be stopped (error %d).", int(syscall.EINVAL)) {
		t.Errorf("failed: %v", err)
	}
	unsupported := newFakeProc([]int{14}, starts, nil)
	unsupported.terminateError = proc.ErrNotMeasurable
	_, err = stopSession(t, sb, CLIClaude, activitySid(14), unsupported, fastStop)
	if stopStatusOf(err) != 500 || err.Error() != "Sessions cannot be stopped on this system." {
		t.Errorf("unsupported: %v", err)
	}
}

func TestStopRealAdapter(t *testing.T) { // Swift: ActivityStopTests "the real adapter ends a child process this test spawned, matched by its real start time"
	system := proc.NewSystem()
	if runtime.GOOS != "darwin" || !system.Measurable() {
		t.Skip("the real process adapter exists on darwin only")
	}
	cmd := exec.Command("/bin/sleep", "30")
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }() // reaps the child, so signal 0 stops answering once it is gone
	defer func() { _ = cmd.Process.Kill() }()
	pid := cmd.Process.Pid
	sb := newSandbox(t)
	start, ok := system.StartTime(context.Background(), pid)
	if !ok || !system.IsAlive(context.Background(), pid) {
		t.Fatalf("the child %d is not visible (start %q)", pid, start)
	}
	sb.status(pid, obj{"sessionId": activitySid(50), "procStart": start})
	result, err := Stop(context.Background(), sb.roots, CLIClaude, activitySid(50), system, DefaultStopOptions())
	if err != nil || !result.Exited {
		t.Fatalf("result = %+v, err = %v", result, err)
	}
	var exitErr *exec.ExitError
	if err := <-exited; !errors.As(err, &exitErr) || exitErr.ProcessState.Sys().(syscall.WaitStatus).Signal() != syscall.SIGTERM {
		t.Errorf("the child did not end on SIGTERM: %v", err)
	}
}

func TestSafetyReusedCodexPid(t *testing.T) { // Swift: ActivitySafetyTests "a confirmed threadless row cannot stop a replacement process with the same pid"
	sb := newSandbox(t)
	threads := []proc.Thread{{Pid: 71}}
	original := newFakeProc([]int{71}, map[int]string{71: stopStart}, threads)
	report := sb.read(original)
	var row *Session
	for i := range report.Sessions {
		if report.Sessions[i].Pid == 71 {
			row = &report.Sessions[i]
		}
	}
	if row == nil {
		t.Fatal("no row for pid 71")
	}
	// The confirmation keeps the original row while the OS reuses its pid.
	expectRefusal(t, sb, CLICodex, row.ID, newFakeProc([]int{71}, map[int]string{71: replacementStart}, threads), StopOptions{})
	expectRefusal(t, sb, CLICodex, row.ID, newFakeProc([]int{71}, nil, threads), StopOptions{})
	expectRefusal(t, sb, CLICodex, row.ID, newFakeProc([]int{71}, map[int]string{71: "unavailable"}, threads), StopOptions{})
	// The same observed process remains stoppable, including ps whitespace variation.
	same := newFakeProc([]int{71}, map[int]string{71: "Mon Nov  2  11:00:00  2026"}, threads)
	if r, err := stopSession(t, sb, CLICodex, row.ID, same, StopOptions{}); err != nil || !r.Exited {
		t.Fatalf("same process: %+v %v", r, err)
	}
	if got := same.killedPids(); len(got) != 1 || got[0] != 71 {
		t.Errorf("killed = %v", got)
	}
}

func TestSafetyMissingIdentity(t *testing.T) { // Swift: ActivitySafetyTests "unknown and legacy bare pid rows never authorize Stop"
	sb := newSandbox(t)
	threads := []proc.Thread{{Pid: 72}}
	report := sb.read(newFakeProc([]int{72}, nil, threads))
	var row *Session
	for i := range report.Sessions {
		if report.Sessions[i].Pid == 72 {
			row = &report.Sessions[i]
		}
	}
	if row == nil || row.AgeMs != nil {
		t.Fatalf("row = %+v", row)
	}
	for _, id := range []string{row.ID, "pid:72", "pid:72:unknown", "pid:72:invalid"} {
		expectRefusal(t, sb, CLICodex, id, newFakeProc([]int{72}, map[int]string{72: stopStart}, threads), StopOptions{})
	}
}

func TestSafetyInvalidStatusTimestamps(t *testing.T) { // Swift: ActivitySafetyTests "malformed numeric status timestamps produce an unknown title and safe ages"
	sb := newSandbox(t)
	for _, value := range []string{"1e30", "-1e30", "1e309", "-1e309", "253402300800000", "-62167219200001"} {
		sb.put(".claude/sessions/73.json", fmt.Sprintf(`{"pid":73,"sessionId":"timestamp-test","status":"idle","startedAt":%s,"statusUpdatedAt":%s}`, value, value), 0)
		report := sb.read(newFakeProc([]int{73}, nil, nil))
		row := mustSession(t, report, "timestamp-test")
		eq(t, value+" title", row.Title, "unknown date · timestam")
		if row.AgeMs != nil {
			t.Errorf("%s: ageMs = %v", value, *row.AgeMs)
		}
		eq(t, value+" lastWriteAgoMs", *row.LastWriteAgoMs, 0.0)
		if _, err := json.Marshal(report); err != nil {
			t.Errorf("%s: the report does not encode: %v", value, err)
		}
	}
	sb.status(73, nil)
	row := mustSession(t, sb.read(newFakeProc([]int{73}, nil, nil)), activitySid(73))
	eq(t, "valid ageMs", *row.AgeMs, 3_600_000.0)
	eq(t, "valid lastWriteAgoMs", *row.LastWriteAgoMs, 3_000_000.0)
	if len(row.Title) < 10 || row.Title[:10] != "2026-11-02" {
		t.Errorf("title = %q", row.Title)
	}
}

func TestSafetyTimeBounds(t *testing.T) { // Swift: ActivitySafetyTests "time conversion rejects non-finite and out-of-domain inputs before integer arithmetic" (the SessionTitles.pick lines; the rest is internal/textjs)
	for _, v := range []float64{math.NaN(), math.Inf(1), math.Inf(-1), 1.7976931348623157e308, -1.7976931348623157e308, 9.223372036854775807e18} {
		v := v
		eq(t, fmt.Sprint(v), pickTitle(nil, &v, "test"), "unknown date · test")
	}
}
