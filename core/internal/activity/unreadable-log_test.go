package activity

import (
	"os"
	"testing"

	"spacevibe.dev/core/internal/proc"
)

// A log that exists but cannot be read is not "no rollout" / "no transcript": the row names the real problem with a
// sentence of its own (finding 10). chmod 000 does not stop root, so the tests skip there.
func skipIfRoot(t *testing.T) {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Skip("root reads a file with mode 000")
	}
}

func TestCodexUnreadableRolloutHasItsOwnReason(t *testing.T) {
	skipIfRoot(t)
	sb := newSandbox(t)
	x := codexRecords{activityUUID(120)}
	path := sb.codexLog(x.id, []obj{x.meta(activityNowMs-5000, "/work/x", nil), x.started(activityNowMs - 4000)}, 0)
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(path, 0o644)
	report := sb.read(newFakeProc(nil, map[int]string{4120: "Mon Nov  2 11:00:00 2026"}, []proc.Thread{{Pid: 4120, ThreadID: x.id}}))
	s := mustSession(t, report, x.id)
	eq(t, "state", s.State, StateUnmeasurable)
	eq(t, "reason", *s.ReasonCode, ReasonCodexRolloutUnreadable)
	eq(t, "text", s.StateReason, ReasonCodexRolloutUnreadable.Text())
	if *s.ReasonCode == ReasonCodexNoRollout || s.StateReason == ReasonCodexNoRollout.Text() {
		t.Error("an unreadable rollout was reported as no rollout")
	}
}

func TestClaudeUnreadableTranscriptHasItsOwnNote(t *testing.T) {
	skipIfRoot(t)
	sb := newSandbox(t)
	sb.status(130, obj{"status": "idle", "statusUpdatedAt": activityNowMs - 5000})
	c := claudeRecords{cwd: "/work/app", session: activitySid(130)}
	path := sb.claudeLog("/work/app", c.session, []obj{c.user("hello", activityNowMs-4000)}, 0)
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(path, 0o644)
	s := mustSession(t, sb.read(newFakeProc([]int{130}, nil, nil)), activitySid(130))
	eq(t, "costNote", *s.CostNote, transcriptUnreadable)
	if *s.CostNote == noTranscript {
		t.Error("an unreadable transcript was reported as no transcript")
	}
	if s.Cost != nil {
		t.Error("no readable transcript, no cost")
	}
}
