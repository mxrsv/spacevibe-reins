package limits

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"runtime"
	"strings"
	"testing"
	"time"
)

// G-fix.11: reads of the Claude cache, the Codex logs and the snapshots go through an open-regular helper that
// refuses a FIFO without waiting and caps the size.

func withinFiveSeconds(t *testing.T, what string, f func()) {
	t.Helper()
	done := make(chan struct{})
	go func() { f(); close(done) }()
	select {
	case <-done:
	case <-after5s():
		t.Fatalf("%s blocked on a FIFO", what)
	}
}

func TestClaudeStateFIFOIsUnreadable(t *testing.T) {
	h := newTempHome(t)
	// The roots are resolved before the FIFO exists: roots.Resolve under SPACEVIBE_TEST=1 opens every root path
	// (canonicalCase, O_EVTONLY) and that open blocks on a FIFO. That is a roots finding, not a limits one.
	r, cfg := h.roots(), h.cfg()
	mkfifo(t, h.path(".claude/.claude.json"))
	withinFiveSeconds(t, "Read", func() {
		result, err := Read(t.Context(), cfg, r, time.Unix(testNow, 0))
		if err != nil || result.Limits[0].State != Unreadable {
			t.Errorf("state = %s, err %v", result.Limits[0].State, err)
		}
	})
	withinFiveSeconds(t, "AccountKey", func() {
		if _, ok := AccountKey(r); ok {
			t.Error("a FIFO gave an account key")
		}
	})
}

func TestClaudeStateSizeCap(t *testing.T) {
	h := newTempHome(t)
	path := h.write(".claude/.claude.json", "{}")
	if err := os.Truncate(path, maxCacheBytes+1); err != nil { // sparse: no disk used
		t.Fatal(err)
	}
	if e := h.claude(testNow); e.State != Unreadable {
		t.Errorf("a state file past the cap: %s", e.State)
	}
	// Exactly the cap is read (and is not JSON: zeros), still unreadable but by the parser, not the cap.
	if err := os.Truncate(path, maxCacheBytes); err != nil {
		t.Fatal(err)
	}
	if e := h.claude(testNow); e.State != Unreadable {
		t.Errorf("a zero-filled state file: %s", e.State)
	}
	// The account key reads at most 16 MiB.
	if err := os.WriteFile(path, []byte(`{"oauthAccount":{"accountUuid":"a"},"pad":"`+strings.Repeat("x", maxStateBytes)+`"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, ok := AccountKey(h.roots()); ok {
		t.Error("a state file past 16 MiB gave an account key")
	}
}

func TestStateIsAFolderIsUnreadable(t *testing.T) {
	h := newTempHome(t)
	h.mkdir(".claude/.claude.json")
	if e := h.claude(testNow); e.State != Unreadable {
		t.Errorf("state = %s", e.State)
	}
}

func TestCodexLogFIFOIsSkippedOrRefused(t *testing.T) {
	h := newTempHome(t)
	h.mkdir(".codex")
	fifo := h.path(".codex/sessions/2026/11/03/rollout-fifo.jsonl")
	mkfifo(t, fifo)
	withinFiveSeconds(t, "Read", func() {
		// Walk lists only regular files, so a FIFO is never opened: nothing recorded.
		if e := h.read(testNow).Limits[1]; e.State != NotRecorded {
			t.Errorf("state = %s", e.State)
		}
	})
	withinFiveSeconds(t, "lastEvent", func() {
		if _, outcome := lastEvent(fifo); outcome != eventFailed {
			t.Errorf("outcome = %d, want failed", outcome)
		}
	})
}

func TestSnapshotReadRefusesFIFOAndOversize(t *testing.T) {
	h := newTempHome(t)
	fifo := h.path(".spacevibe/claude-limits/fifo.json")
	mkfifo(t, fifo)
	withinFiveSeconds(t, "ReadSnapshot", func() {
		if _, ok := ReadSnapshot(fifo); ok {
			t.Error("a FIFO was read")
		}
	})
	big := h.write(".spacevibe/claude-limits/big.json", `{"a":"`+strings.Repeat("x", MaxSnapshotBytes)+`"}`)
	if _, ok := ReadSnapshot(big); ok {
		t.Error("an oversized snapshot was read")
	}
	exact := h.write(".spacevibe/claude-limits/exact.json", `{"a":"`+strings.Repeat("x", MaxSnapshotBytes-8)+`"}`)
	if _, ok := ReadSnapshot(exact); !ok {
		t.Error("a snapshot of exactly the cap was refused")
	}
	if _, ok := ReadSnapshot(h.path("nothing.json")); ok {
		t.Error("a missing file was read")
	}
}

// G-fix.15 (presence part): a denied parent folder reads as unreadable, not as notRecorded or notInstalled.
func TestDeniedParentReadsAsUnreadable(t *testing.T) {
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("needs a user whose permissions are enforced")
	}
	t.Run("claude state behind a denied folder", func(t *testing.T) {
		h := newTempHome(t)
		h.write(".claude/.claude.json", claudeCache("", twoWeekly))
		deny(t, h.path(".claude"))
		if e := h.claude(testNow); e.State != Unreadable {
			t.Errorf("state = %s (Swift read notRecorded here)", e.State)
		}
	})
	t.Run("every root behind a denied home", func(t *testing.T) {
		h := newTempHome(t)
		h.mkdir(".claude")
		h.mkdir(".codex")
		h.mkdir(".gemini")
		deny(t, h.root)
		for _, e := range h.read(testNow).Limits {
			if e.State != Unreadable {
				t.Errorf("%s: state = %s (Swift read notInstalled or notRecorded here)", e.CLI, e.State)
			}
		}
	})
}

func deny(t *testing.T, path string) {
	t.Helper()
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(path, 0o755) })
}

func TestReadHonorsCancellation(t *testing.T) {
	h := newTempHome(t)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	h.write(".claude/.claude.json", accountState(defaultAcc))
	h.weekly("s", "1", statusNow)
	if _, err := Read(ctx, h.cfg(), h.roots(), time.Unix(int64(statusNow), 0)); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v", err)
	}
}

// The wire shape of docs/internals/core-protocol.md: every nullable member is present with null, windows is [].
func TestResultJSONShape(t *testing.T) {
	h := newTempHome(t)
	data, err := json.Marshal(h.read(testNow))
	if err != nil {
		t.Fatal(err)
	}
	const entry = `{"cli":"%s","state":"notInstalled","plan":null,"source":null,"at":null,"windows":[]}`
	want := `{"limits":[` + strings.ReplaceAll(entry, "%s", "claude") + "," + strings.ReplaceAll(entry, "%s", "codex") + "," +
		strings.ReplaceAll(entry, "%s", "gemini") + `]}`
	if string(data) != want {
		t.Fatalf("got  %s\nwant %s", data, want)
	}

	h.write(".claude/.claude.json", claudeCache("", twoWeekly))
	data, _ = json.Marshal(h.read(testNow).Limits[0])
	const wantMeasured = `{"cli":"claude","state":"measured","plan":null,"source":"claudeCache","at":1793500000.25,"windows":[` +
		`{"id":"weekly_all","minutes":10080,"scope":null,"usedPercent":8,"resetsAt":1793980800.803,"active":true,"current":true},` +
		`{"id":"weekly_scoped:Fable","minutes":10080,"scope":"Fable","usedPercent":0,"resetsAt":1793980799.803,"active":false,"current":true}]}`
	if string(data) != wantMeasured {
		t.Fatalf("got  %s\nwant %s", data, wantMeasured)
	}
}
