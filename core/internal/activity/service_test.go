package activity

import (
	"context"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"spacevibe.dev/core/internal/proc"
)

// The subscribe loop (contract cases activity_subscribe_snapshot, activity_notification_on_change and
// activity_resync_after_restart): a full snapshot first, then a full report only when the encoding changed.

type collector struct {
	mu      sync.Mutex
	reports []Report
}

func (c *collector) add(r Report) {
	c.mu.Lock()
	c.reports = append(c.reports, r)
	c.mu.Unlock()
}

func (c *collector) count() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.reports)
}

func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(2 * time.Millisecond)
	}
}

func startWatch(t *testing.T, s *Service, c *collector) (stop func() error) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Watch(ctx, 3*time.Millisecond, c.add) }()
	t.Cleanup(cancel)
	return func() error {
		cancel()
		return <-done
	}
}

func TestWatchSnapshotThenOnlyChanges(t *testing.T) {
	sb := newSandbox(t)
	a := claudeRecords{cwd: "/work/app-a", session: activitySid(131)}
	path := sb.claudeLog("/work/app-a", activitySid(131), []obj{a.user("go", activityMinutes(60)), a.tool("w1", "Bash", obj{"command": "make"}, activityMinutes(50))}, 3_600_000)
	s := NewService(sb.roots, newFakeProc(nil, nil, nil), DefaultOptions(), func() time.Time { return activityNow })
	c := &collector{}
	stop := startWatch(t, s, c)

	waitFor(t, "the snapshot", func() bool { return c.count() >= 1 })
	time.Sleep(60 * time.Millisecond) // many polls with nothing new: the core stays silent
	if n := c.count(); n != 1 {
		t.Fatalf("%d reports for an unchanged home, want the snapshot only", n)
	}
	if len(c.reports[0].Files)+len(c.reports[0].Failures)+c.reports[0].Stats.Logs == 0 || c.reports[0].Stats.Logs != 1 {
		t.Fatalf("the snapshot is not a full read: %+v", c.reports[0].Stats)
	}

	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = f.WriteString(activityJSON(a.result("w1", "Exit code 1\nError: nope", true, activityMinutes(49))) + "\n")
	_ = f.Close()
	waitFor(t, "the notification", func() bool { return c.count() >= 2 })
	last := c.reports[1]
	if len(last.Failures) != 1 || last.Failures[0].Title != "make" {
		t.Errorf("the pushed report is not full: %+v", last.Failures)
	}
	if err := stop(); err != context.Canceled {
		t.Errorf("Watch returned %v after cancel", err)
	}
	n := c.count()
	time.Sleep(20 * time.Millisecond)
	if c.count() != n {
		t.Error("a report was pushed after the watch ended")
	}
}

func TestWatchLiveSessionChangesWithTheClock(t *testing.T) {
	sb := newSandbox(t)
	sb.status(141, obj{"status": "idle"})
	var ticks atomic.Int64
	clock := func() time.Time { return activityNow.Add(time.Duration(ticks.Add(1)) * time.Second) }
	s := NewService(sb.roots, newFakeProc([]int{141}, nil, nil), DefaultOptions(), clock)
	c := &collector{}
	stop := startWatch(t, s, c)
	waitFor(t, "three reports", func() bool { return c.count() >= 3 })
	_ = stop()
}

func TestWatchResyncAfterRestart(t *testing.T) {
	sb := newSandbox(t)
	a := claudeRecords{cwd: "/work/app-a", session: activitySid(151)}
	sb.claudeLog("/work/app-a", activitySid(151), []obj{a.user("go", activityMinutes(60)), a.tool("r1", "Bash", obj{"command": "make"}, activityMinutes(50)), a.result("r1", "Exit code 1\nError: nope", true, activityMinutes(49))}, 3_600_000)
	clock := func() time.Time { return activityNow }
	first := NewService(sb.roots, newFakeProc(nil, nil, nil), DefaultOptions(), clock)
	want, err := first.Read(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	// A new service has an empty engine, as after a core restart: its snapshot is the same full report.
	second := NewService(sb.roots, newFakeProc(nil, nil, nil), DefaultOptions(), clock)
	c := &collector{}
	stop := startWatch(t, second, c)
	waitFor(t, "the snapshot", func() bool { return c.count() >= 1 })
	_ = stop()
	if !equalReports(c.reports[0], want) {
		t.Error("the snapshot after a restart differs from a full read")
	}
}

func TestWatchCancelledBeforeSnapshot(t *testing.T) {
	sb := newSandbox(t)
	s := NewService(sb.roots, newFakeProc(nil, nil, nil), DefaultOptions(), nil)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	emitted := false
	err := s.Watch(ctx, time.Millisecond, func(Report) { emitted = true })
	if err != context.Canceled || emitted {
		t.Errorf("err = %v, emitted = %v", err, emitted)
	}
}

func TestServiceStopTakesNoPid(t *testing.T) {
	sb := newSandbox(t)
	sb.status(161, obj{"procStart": stopStart})
	p := newFakeProc([]int{161}, map[int]string{161: stopStart}, []proc.Thread{})
	s := NewService(sb.roots, p, DefaultOptions(), nil)
	// activity.stop {cli, id}: an id the system does not know is a 404 and signals nothing (contract case stop_refuses_unknown).
	if _, err := s.Stop(context.Background(), CLIClaude, "no-such-session"); stopStatusOf(err) != 404 {
		t.Errorf("unknown id: %v", err)
	}
	if len(p.killedPids()) != 0 {
		t.Errorf("signalled %v", p.killedPids())
	}
	if r, err := s.Stop(context.Background(), CLIClaude, activitySid(161)); err != nil || !r.Exited {
		t.Errorf("known id: %+v %v", r, err)
	}
}
