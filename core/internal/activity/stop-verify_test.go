package activity

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/proc"
)

// G-fix.10 (SE L1, SF 13, SF 14): Stop reads the process identity with the pid and again right before the signal,
// and tells "cannot verify" (409) from "no longer running" (404). Go-only: Swift has neither.

const cannotVerify = "That session could not be verified, so nothing was stopped."

func stopErrorText(t *testing.T, err error) string {
	t.Helper()
	if err == nil {
		t.Fatal("Stop succeeded")
	}
	return err.Error()
}

func TestStopRefusesWhenIdentityChangesBeforeKill(t *testing.T) {
	sb := newSandbox(t)
	sb.status(15, obj{"procStart": stopStart})
	codexID, _ := codexProcessID(23, stopStart, true)
	threads := []proc.Thread{{Pid: 23}, {Pid: 24, ThreadID: activityUUID(24)}}
	for name, c := range map[string]struct {
		cli CLI
		id  string
		p   *fakeProc
	}{
		"claude, pid reused (start changes)": {CLIClaude, activitySid(15), func() *fakeProc {
			p := newFakeProc([]int{15}, map[int]string{15: stopStart}, nil)
			p.laterStarts = map[int]string{15: replacementStart}
			return p
		}()},
		"claude, same start but another program": {CLIClaude, activitySid(15), func() *fakeProc {
			p := newFakeProc([]int{15}, map[int]string{15: stopStart}, nil)
			p.names, p.laterNames = map[int]string{15: "claude"}, map[int]string{15: "vim"}
			return p
		}()},
		"codex thread, pid reused": {CLICodex, activityUUID(24), func() *fakeProc {
			p := newFakeProc([]int{24}, map[int]string{24: stopStart}, threads)
			p.laterStarts = map[int]string{24: replacementStart}
			return p
		}()},
		"codex thread-less, name changes": {CLICodex, codexID, func() *fakeProc {
			p := newFakeProc([]int{23}, map[int]string{23: stopStart}, threads)
			p.names, p.laterNames = map[int]string{23: "codex"}, map[int]string{23: "zsh"}
			return p
		}()},
		"process exits between lookup and kill": {CLIClaude, activitySid(15), func() *fakeProc {
			p := newFakeProc([]int{15}, map[int]string{15: stopStart}, nil)
			p.laterErrors = map[int]error{15: proc.ErrNoSuchProcess}
			return p
		}()},
	} {
		t.Run(name, func(t *testing.T) {
			_, err := stopSession(t, sb, c.cli, c.id, c.p, fastStop)
			if stopStatusOf(err) != 404 || stopErrorText(t, err) != "That session is no longer running." {
				t.Errorf("err = %v", err)
			}
			if got := c.p.killedPids(); len(got) != 0 {
				t.Errorf("signalled %v", got)
			}
		})
	}
}

func TestStopCannotVerifyIsNotNoLongerRunning(t *testing.T) {
	sb := newSandbox(t)
	sb.status(16, obj{"procStart": stopStart})
	starts := map[int]string{16: stopStart}
	codexID, _ := codexProcessID(25, stopStart, true)
	for name, c := range map[string]struct {
		cli CLI
		id  string
		p   *fakeProc
	}{
		"claude: ps fails for the pid": {CLIClaude, activitySid(16), func() *fakeProc {
			p := newFakeProc([]int{16}, starts, nil)
			p.identifyErrors = map[int]error{16: proc.ErrUnknown}
			return p
		}()},
		"claude: start unknown": {CLIClaude, activitySid(16), newFakeProc([]int{16}, nil, nil)},
		"claude: ps fails on the re-check": {CLIClaude, activitySid(16), func() *fakeProc {
			p := newFakeProc([]int{16}, starts, nil)
			p.laterErrors = map[int]error{16: proc.ErrUnknown}
			return p
		}()},
		"codex: process list unknown": {CLICodex, activityUUID(26), func() *fakeProc {
			p := newFakeProc([]int{26}, starts, []proc.Thread{{Pid: 26, ThreadID: activityUUID(26)}})
			p.threadsError = proc.ErrUnknown
			return p
		}()},
		"codex: lock listing failed, id is a thread": {CLICodex, activityUUID(26), newFakeProc([]int{26}, starts, []proc.Thread{{Pid: 26, LockUnknown: true}})},
		"codex: lock listing failed, id is a pid":    {CLICodex, codexID, newFakeProc([]int{25}, map[int]string{25: stopStart}, []proc.Thread{{Pid: 25, LockUnknown: true}})},
		"codex: ps fails for the thread-less pid": {CLICodex, codexID, func() *fakeProc {
			p := newFakeProc([]int{25}, map[int]string{25: stopStart}, []proc.Thread{{Pid: 25}})
			p.identifyErrors = map[int]error{25: proc.ErrUnknown}
			return p
		}()},
	} {
		t.Run(name, func(t *testing.T) {
			_, err := stopSession(t, sb, c.cli, c.id, c.p, fastStop)
			if stopStatusOf(err) != 409 || stopErrorText(t, err) != cannotVerify {
				t.Errorf("err = %v", err)
			}
			if got := c.p.killedPids(); len(got) != 0 {
				t.Errorf("signalled %v", got)
			}
		})
	}
}

func TestStopFindsTheSessionBesideAnUnknownLock(t *testing.T) {
	sb := newSandbox(t)
	p := newFakeProc([]int{27, 28}, map[int]string{27: stopStart}, []proc.Thread{{Pid: 28, LockUnknown: true}, {Pid: 27, ThreadID: activityUUID(27)}})
	if r, err := stopSession(t, sb, CLICodex, activityUUID(27), p, fastStop); err != nil || !r.Exited {
		t.Fatalf("%+v %v", r, err)
	}
	if got := p.killedPids(); len(got) != 1 || got[0] != 27 {
		t.Errorf("killed %v", got)
	}
}

func TestStopUnreadableSessionsFolderIsNotNoLongerRunning(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads every folder")
	}
	p := func() *fakeProc { return newFakeProc([]int{17}, map[int]string{17: stopStart}, nil) }
	t.Run("folder missing: nothing is running", func(t *testing.T) {
		sb := newSandbox(t)
		expectRefusal(t, sb, CLIClaude, activitySid(17), p(), fastStop)
	})
	t.Run("folder unreadable", func(t *testing.T) {
		sb := newSandbox(t)
		sb.status(17, obj{"procStart": stopStart})
		dir := filepath.Join(sb.roots.Claude.Root, "sessions")
		if err := os.Chmod(dir, 0); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
		fake := p()
		expectRefusalStatus(t, sb, CLIClaude, activitySid(17), fake, fastStop, 409)
	})
	t.Run("sessions is a file", func(t *testing.T) {
		sb := newSandbox(t)
		sb.write(".claude/sessions", []byte("x"))
		expectRefusalStatus(t, sb, CLIClaude, activitySid(17), p(), fastStop, 409)
	})
	t.Run("a status file cannot be read", func(t *testing.T) {
		sb := newSandbox(t)
		sb.status(17, obj{"procStart": stopStart})
		file := filepath.Join(sb.roots.Claude.Root, "sessions", "17.json")
		if err := os.Chmod(file, 0); err != nil {
			t.Fatal(err)
		}
		expectRefusalStatus(t, sb, CLIClaude, activitySid(17), p(), fastStop, 409)
	})
	t.Run("a vanished or non-regular entry is not unreadable", func(t *testing.T) {
		sb := newSandbox(t)
		dir := filepath.Join(sb.roots.Claude.Root, "sessions")
		if err := os.MkdirAll(filepath.Join(dir, "18.json"), 0o755); err != nil { // a directory named like a status file
			t.Fatal(err)
		}
		expectRefusal(t, sb, CLIClaude, activitySid(17), p(), fastStop)
	})
}

func TestStopOnAnOsThatCannotMeasure(t *testing.T) {
	sb := newSandbox(t)
	sb.status(19, obj{"procStart": stopStart})
	p := newFakeProc(nil, nil, nil)
	p.notMeasurable = true
	_, err := stopSession(t, sb, CLIClaude, activitySid(19), p, fastStop)
	if stopStatusOf(err) != 500 || stopErrorText(t, err) != "Sessions cannot be stopped on this system." {
		t.Errorf("err = %v", err)
	}
}

func TestStopMessagesNeverQuoteTheId(t *testing.T) {
	sb := newSandbox(t)
	id := "SECRET-session-id"
	p := newFakeProc(nil, nil, nil)
	p.threadsError = proc.ErrUnknown
	for _, cli := range []CLI{CLIClaude, CLICodex} {
		_, err := stopSession(t, sb, cli, id, p, fastStop)
		if err == nil || strings.Contains(err.Error(), id) {
			t.Errorf("%s: %v", cli, err)
		}
	}
}

// G-fix.10 on the read path: a failed ps or lsof is "not measured", never an empty list, never "no rollout yet".
func TestReadMarksUnknownCodexProcessesNotMeasured(t *testing.T) {
	sb := newSandbox(t)

	t.Run("lock listing failed: the row is not measured", func(t *testing.T) {
		p := newFakeProc([]int{4301}, map[int]string{4301: stopStart}, []proc.Thread{{Pid: 4301, LockUnknown: true}})
		report := sb.read(p)
		var row *Session
		for i := range report.Sessions {
			if report.Sessions[i].Pid == 4301 {
				row = &report.Sessions[i]
			}
		}
		if row == nil {
			t.Fatalf("no row: %+v", report.Sessions)
		}
		eq(t, "state", row.State, StateUnmeasurable)
		eq(t, "reason", *row.ReasonCode, ReasonCodexProcessUnknown)
		eq(t, "id cannot authorize stop", row.ID, "pid:4301:unknown")
		eq(t, "text", row.StateReason, ReasonCodexProcessUnknown.Text())
		if strings.Contains(row.StateReason, "first prompt") || strings.Contains(*row.CostNote, "first prompt") {
			t.Errorf("claims the rollout does not exist yet: %q / %q", row.StateReason, *row.CostNote)
		}
		eq(t, "limits stay fixed", len(report.Unmeasurable), len(limitCodes))
		expectRefusalStatus(t, sb, CLICodex, row.ID, p, fastStop, 409)
	})

	t.Run("process list failed: one extra limit instead of silence", func(t *testing.T) {
		p := newFakeProc(nil, nil, nil)
		p.threadsError = proc.ErrUnknown
		report := sb.read(p)
		eq(t, "sessions", len(report.Sessions), 0)
		eq(t, "limits", len(report.Unmeasurable), len(limitCodes)+1)
		last := report.Unmeasurable[len(report.Unmeasurable)-1]
		eq(t, "last limit", last, Limit{CLI: CLICodex, Code: ReasonCodexProcessUnknown, Text: ReasonCodexProcessUnknown.Text()})
	})

	t.Run("a healthy read lists no unknown limit", func(t *testing.T) {
		eq(t, "limits", len(sb.read(newFakeProc(nil, nil, nil)).Unmeasurable), len(limitCodes))
	})
}

// A live process whose status file names the right session but gives no start time that can be compared is not "gone":
// the session may well be running, so Stop says it cannot verify (409) and signals nothing. A dead pid is still 404.
func TestStopStatusFileWithoutAUsableStartIsCannotVerify(t *testing.T) {
	const pid = 31
	body := func(procStart string) string {
		return `{"pid":31,"sessionId":"` + activitySid(pid) + `","status":"idle"` + procStart + `}`
	}
	for name, c := range map[string]struct {
		file  string
		alive bool
		want  int
		text  string
	}{
		"procStart missing":       {body(""), true, 409, cannotVerify},
		"procStart null":          {body(`,"procStart":null`), true, 409, cannotVerify},
		"procStart not a string":  {body(`,"procStart":1793900000`), true, 409, cannotVerify},
		"procStart empty":         {body(`,"procStart":""`), true, 409, cannotVerify},
		"procStart unparsable":    {body(`,"procStart":"yesterday-ish"`), true, 409, cannotVerify},
		"dead pid, no procStart":  {body(""), false, 404, "That session is no longer running."},
		"reused pid, both parsed": {body(`,"procStart":"Mon Nov  2 10:00:00 2026"`), true, 404, "That session is no longer running."},
	} {
		t.Run(name, func(t *testing.T) {
			sb := newSandbox(t)
			sb.put(".claude/sessions/31.json", c.file, 0)
			var alive []int
			if c.alive {
				alive = []int{pid}
			}
			p := newFakeProc(alive, map[int]string{pid: stopStart}, nil)
			_, err := stopSession(t, sb, CLIClaude, activitySid(pid), p, fastStop)
			if stopStatusOf(err) != c.want || stopErrorText(t, err) != c.text {
				t.Errorf("err = %v, want %d %q", err, c.want, c.text)
			}
			if got := p.killedPids(); len(got) != 0 {
				t.Errorf("signalled %v", got)
			}
		})
	}
}
