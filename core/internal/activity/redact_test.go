package activity

import (
	"encoding/json"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/hashes"
)

// A credential typed in a command or echoed in its error never reaches the wire, while the failure key and the hook
// hash stay the hashes of the raw text.
func TestCredentialsAreMaskedOnTheWire(t *testing.T) {
	sb := newSandbox(t)
	m := activityMinutes
	const curl = `curl -fsS -H "Authorization: Bearer abc123" https://api.dev/x`
	const hook = "TOKEN=hookpw123 sh /h/check.sh"
	c := claudeRecords{cwd: "/work/app", session: activitySid(91)}
	sb.status(91, obj{"status": "busy"})
	sb.claudeLog("/work/app", activitySid(91), []obj{
		c.user("call the api", m(30)),
		c.tool("c1", "Bash", obj{"command": curl}, m(20)),
		c.result("c1", "Exit code 22\ncurl: (22) The requested URL returned error: 401 Authorization: Bearer abc123", true, m(19)),
		c.hookFail(1, "Stop", hook, m(10)),
		c.tool("c2", "Bash", obj{"command": "OPENAI_API_KEY=sk-live-pw456 run"}, activityNowMs-2000),
	}, 2000)
	report := sb.read(newFakeProc([]int{91}, nil, nil))

	data, err := json.Marshal(report)
	if err != nil {
		t.Fatal(err)
	}
	for _, leak := range []string{"abc123", "hookpw123", "sk-live-pw456"} {
		if strings.Contains(string(data), leak) {
			t.Errorf("%q escaped: %s", leak, data)
		}
	}

	failure, ok := findFailure(report, func(f Failure) bool { return f.Kind == KindCommand })
	if !ok {
		t.Fatal("no command failure")
	}
	eq(t, "title", failure.Title, `curl -fsS -H "Authorization: Bearer `+"•••"+`" https://api.dev/x`)
	eq(t, "key is the hash of the raw command", failure.Key, hashes.Sha(normalizeCommand(curl)))
	hookFailure, ok := findFailure(report, func(f Failure) bool { return f.Kind == KindHook })
	if !ok {
		t.Fatal("no hook failure")
	}
	eq(t, "hook title", hookFailure.Title, "TOKEN=••• sh /h/check.sh")
	eq(t, "hook hash is of the raw command", hookFailure.Hook.Hash, hashes.HookHash("Stop", hook))
	eq(t, "hook key", hookFailure.Key, hashes.HookHash("Stop", hook))

	s := mustSession(t, report, activitySid(91))
	if s.CurrentTool == nil || s.CurrentTool.Target != "OPENAI_API_KEY=••• run" {
		t.Errorf("current tool = %+v", s.CurrentTool)
	}
}

// A command longer than the title is masked before it is cut, so a cut cannot leave half of a credential.
func TestFailureTitleMasksBeforeItCuts(t *testing.T) {
	title := failureTitle(strings.Repeat("x", 100) + " --token ghp_abcdefghij0123456789abcdefghij")
	if strings.Contains(title, "ghp_") || !strings.Contains(title, "•••") {
		t.Errorf("title = %q", title)
	}
}

// The running-tool target is masked before the 160-character preview cut, so a credential that straddles the cut
// leaves no first characters on the wire.
func TestToolTargetMasksBeforeItCuts(t *testing.T) {
	sb := newSandbox(t)
	const token = "abcdef0123456789"
	command := strings.Repeat("x", 150) + " Bearer " + token + " tail"
	if i := strings.Index(command, token); i >= previewLen || i+len(token) <= previewLen {
		t.Fatalf("the token does not straddle the cut: starts at %d", i)
	}
	c := claudeRecords{cwd: "/work/app", session: activitySid(92)}
	sb.status(92, obj{"status": "busy"})
	sb.claudeLog("/work/app", activitySid(92), []obj{
		c.user("go", activityMinutes(5)),
		c.tool("t1", "Bash", obj{"command": command}, activityNowMs-2000),
	}, 2000)
	s := mustSession(t, sb.read(newFakeProc([]int{92}, nil, nil)), activitySid(92))
	if s.CurrentTool == nil || strings.Contains(s.CurrentTool.Target, "abc") || !strings.Contains(s.CurrentTool.Target, "Bearer •") {
		t.Errorf("current tool = %+v", s.CurrentTool)
	}
}
