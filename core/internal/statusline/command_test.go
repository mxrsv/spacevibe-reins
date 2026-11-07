//go:build unix

package statusline

import (
	"bytes"
	"errors"
	"io"
	"os"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/limits"
)

// streams are the files standing in for Claude's stdout and stderr. Like the real ones they are *os.File, so the
// original command writes to them directly, with no copying goroutine beside the collector's own messages.
func (h tempHome) streams() (out, errs *os.File, read func() (string, string)) {
	h.t.Helper()
	open := func(name string) *os.File {
		f, err := os.Create(h.path(name))
		if err != nil {
			h.t.Fatal(err)
		}
		h.t.Cleanup(func() { f.Close() })
		return f
	}
	out, errs = open("stdout"), open("stderr")
	return out, errs, func() (string, string) { return h.text("stdout"), h.text("stderr") }
}

// run runs `statusline capture` in process against h, with its environment, and returns the exit status and what
// reached stdout and stderr.
func (h tempHome) run(stdin io.Reader, original string) (code int, stdout, stderr string) {
	h.t.Helper()
	h.setEnv()
	out, errs, read := h.streams()
	code = Run([]string{"capture", h.path(".spacevibe"), h.path(".claude"), original}, stdin, out, errs)
	stdout, stderr = read()
	return code, stdout, stderr
}

func payload(session string) []byte {
	return input(76, session, int(time.Now().Unix())+86400)
}

// scripts/test-statusline.sh holds the end-to-end versions of these against the built binary.
func TestCaptureCommandPassesThrough(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	in := payload("synthetic-session")
	code, stdout, stderr := h.run(bytes.NewReader(in), "cat; printf 'original-statusline\\n' >&2; exit 7")
	if code != 7 || stdout != string(in) || stderr != "original-statusline\n" {
		t.Fatalf("exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	saved := h.text(".spacevibe/claude-limits/synthetic-session.json")
	if !strings.Contains(saved, `"used_percentage": 76`) || strings.Contains(saved, "must-not-persist") {
		t.Fatalf("snapshot: %s", saved)
	}
	if h.exists(".spacevibe/claude-limits/" + limits.LastErrorFile) {
		t.Fatal("last-error after a good capture")
	}
}

func TestCaptureCommandOversizedInputIsForwardedNotKept(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	good := payload("synthetic-session")
	h.run(bytes.NewReader(good), "cat >/dev/null")
	before := h.text(".spacevibe/claude-limits/synthetic-session.json")

	huge := bytes.Repeat([]byte("x"), limits.MaxInputBytes+1)
	code, stdout, stderr := h.run(bytes.NewReader(huge), "cat; exit 7")
	if code != 7 || stdout != string(huge) {
		t.Fatalf("exit %d, stdout %d bytes", code, len(stdout))
	}
	if stderr != "spacevibe: "+captureFailed+"\n" {
		t.Fatalf("stderr = %q", stderr)
	}
	if h.text(".spacevibe/claude-limits/synthetic-session.json") != before {
		t.Fatal("the snapshot changed")
	}
	if got := h.text(".spacevibe/claude-limits/" + limits.LastErrorFile); got != ReasonInputTooLarge+"\n" {
		t.Fatalf("last-error = %q", got)
	}
}

func TestCaptureCommandExitStatus(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	for name, c := range map[string]struct {
		original string
		want     int
	}{
		"no original":      {"", 0},
		"success":          {"cat >/dev/null", 0},
		"exit 3":           {"cat >/dev/null; exit 3", 3},
		"killed by signal": {"kill -s KILL $$", 128 + 9},
		"stops reading":    {"exit 0", 0},
	} {
		code, _, _ := h.run(bytes.NewReader(bytes.Repeat([]byte("x"), limits.MaxInputBytes+1)), c.original)
		if code != c.want {
			t.Errorf("%s: exit %d, want %d", name, code, c.want)
		}
	}
}

// H6: a shell started through os/exec has the default SIGPIPE, as when Claude starts it. A process that sends itself
// SIGPIPE dies of it (128+13); with the signal ignored it would survive and print.
func TestCaptureCommandOriginalHasDefaultSIGPIPE(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	code, _, stderr := h.run(strings.NewReader("{}"), "kill -s PIPE $$; echo survived >&2")
	if code != 128+13 || strings.Contains(stderr, "survived") {
		t.Fatalf("exit %d, stderr %q", code, stderr)
	}
}

type brokenReader struct{ sent bool }

func (b *brokenReader) Read(p []byte) (int, error) {
	if !b.sent {
		b.sent = true
		return copy(p, "partial"), nil
	}
	return 0, errors.New("read failed")
}

// G-fix.19: a stdin error ends the input, is recorded, and the original still runs to its own exit status.
func TestCaptureCommandStdinError(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	code, stdout, stderr := h.run(&brokenReader{}, "cat; exit 4")
	if code != 4 || stdout != "partial" || !strings.Contains(stderr, "Quota capture failed") {
		t.Fatalf("exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	if got := h.text(".spacevibe/claude-limits/" + limits.LastErrorFile); got != ReasonInputUnreadable+"\n" {
		t.Fatalf("last-error = %q", got)
	}
}

func TestCaptureCommandRefusesAMovedClaudeRoot(t *testing.T) {
	h := newTempHome(t)
	h.account("synthetic-account")
	h.setEnv()
	out, errs, read := h.streams()
	in := payload("s")
	code := Run([]string{"capture", h.path(".spacevibe"), h.path(".another-claude"), "cat"}, bytes.NewReader(in), out, errs)
	if stdout, stderr := read(); code != 0 || stdout != string(in) || !strings.Contains(stderr, "Quota capture failed") {
		t.Fatalf("exit %d, stdout %q, stderr %q", code, stdout, stderr)
	}
	if h.exists(".spacevibe/claude-limits/s.json") || h.text(".spacevibe/claude-limits/"+limits.LastErrorFile) != ReasonClaudeRootChanged+"\n" {
		t.Fatal("a capture ran for another Claude folder, or its reason is not recorded")
	}
}

func TestRunUsage(t *testing.T) {
	for _, args := range [][]string{nil, {"nope"}, {"install", "x"}, {"undo"}, {"undo", "a", "b"}} {
		var out, errs bytes.Buffer
		if code := Run(args, strings.NewReader(""), &out, &errs); code != 2 || !strings.Contains(errs.String(), "Usage:") {
			t.Errorf("%v: exit %d, stderr %q", args, code, errs.String())
		}
	}
	var out, errs bytes.Buffer
	if code := Run([]string{"capture", "only", "two"}, strings.NewReader(""), &out, &errs); code != 1 || !strings.Contains(errs.String(), "Invalid capture arguments.") {
		t.Errorf("capture with 2 args: exit %d, stderr %q", code, errs.String())
	}
}
