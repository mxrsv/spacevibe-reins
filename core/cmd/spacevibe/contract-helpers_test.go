package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/goldentest"
)

// sharedHome is the shared fixture tree plus a private data folder for the case: the CLI roots stay at the
// canonical path, so path-hashed ids match the goldens and a transcript is the same on every run, while the scan
// cache and the write lock never land in the tree the Swift tests and the Go goldens share. The extra env entry
// points SPACEVIBE_HOME at the private folder; pass it to startOn and to any one-shot run.
func sharedHome(t *testing.T) (home string, env []string) {
	t.Helper()
	return canonicalHome(t), []string{"SPACEVIBE_HOME=" + t.TempDir()}
}

// canonicalHome is the shared fixture tree. Never write through it: use sharedHome.
func canonicalHome(t *testing.T) string {
	t.Helper()
	if runtime.GOOS != "darwin" {
		t.Skip("the canonical fixture root is a macOS path (B6)")
	}
	root, err := goldentest.Materialize()
	if err != nil {
		t.Fatal(err)
	}
	return root
}

// copiedHome is a private writable copy of the fixture tree, for cases that write.
func copiedHome(t *testing.T) string {
	t.Helper()
	parent, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(parent, "home")
	if err := goldentest.MaterializeInto(dest); err != nil {
		t.Fatal(err)
	}
	return dest
}

// fixtureEnv points every root at a fixture tree, with the real-home guard on.
func fixtureEnv(home string) []string {
	var env []string
	for k, v := range goldentest.Env(home) {
		env = append(env, k+"="+v)
	}
	return env
}

// startOn runs bin on a fixture tree; the conversation is normalized for its transcript.
func startOn(t *testing.T, bin, home string, env ...string) *core {
	t.Helper()
	c := startCoreIn(t, bin, home, append(fixtureEnv(home), env...)...)
	c.norm = newNormalizer(home)
	for _, e := range env {
		if data, ok := strings.CutPrefix(e, "SPACEVIBE_HOME="); ok {
			c.norm.mask(data, "$DATA")
		}
	}
	return c
}

// startPlain runs bin on an empty temporary home (the default roots), normalized.
func startPlain(t *testing.T, bin string) *core {
	t.Helper()
	c := startCore(t, bin)
	c.norm = newNormalizer(c.home)
	return c
}

// ok returns the result of a reply that must not be an error.
func (c *core) ok(r reply) json.RawMessage {
	c.t.Helper()
	if r.Error != nil {
		c.t.Fatalf("unexpected error %d: %s", r.Error.Code, r.Error.Message)
	}
	return r.Result
}

// status is the `data.status` of a -32000 reply; it fails for any other outcome.
func (c *core) status(r reply) int {
	c.t.Helper()
	c.wantError(r, -32000)
	var d struct {
		Status  int    `json:"status"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(r.Error.Data, &d); err != nil || d.Message != r.Error.Message {
		c.t.Fatalf("bad error data: %s", r.Error.Data)
	}
	return d.Status
}

func decodeInto(t *testing.T, raw json.RawMessage, dst any) {
	t.Helper()
	if err := json.Unmarshal(raw, dst); err != nil {
		t.Fatalf("result does not decode: %v\n%.300s", err, raw)
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func appendFile(t *testing.T, path, content string) {
	t.Helper()
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err := f.WriteString(content); err != nil {
		t.Fatal(err)
	}
}

// editLine is the two Claude log lines of one Edit tool call that succeeded, which the Activity report lists as a
// file row (an edit counts when its result comes back).
func editLine(session, file string, minute int) string {
	ts := "2026-11-02T11:" + twoDigits(minute) + ":00.000Z"
	return `{"type":"assistant","timestamp":"` + ts + `","cwd":"/work/app","sessionId":"` + session +
		`","message":{"id":"msg-` + twoDigits(minute) + `","model":"claude-sonnet-4-6","content":[{"type":"tool_use","id":"e` +
		twoDigits(minute) + `","name":"Edit","input":{"file_path":"` + file + `"}}]}}` + "\n" +
		`{"type":"user","timestamp":"` + ts + `","cwd":"/work/app","sessionId":"` + session +
		`","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"e` + twoDigits(minute) + `","content":"ok"}]}}` + "\n"
}

func twoDigits(n int) string {
	if n < 10 {
		return "0" + string(rune('0'+n))
	}
	return string(rune('0'+n/10)) + string(rune('0'+n%10))
}

const activitySession = "aaaaaa11-0000-4000-8000-000000000000"

// activityLog is the path of the one Claude log the Activity cases use, under a default home.
func activityLog(home string) string {
	return filepath.Join(home, ".claude", "projects", "-work-app", activitySession+".jsonl")
}

// reportFiles lists the file paths of an ActivityReport.
func reportFiles(t *testing.T, raw json.RawMessage) []string {
	t.Helper()
	var rep struct {
		Files []struct {
			Path string `json:"path"`
		} `json:"files"`
	}
	decodeInto(t, raw, &rep)
	var paths []string
	for _, f := range rep.Files {
		paths = append(paths, f.Path)
	}
	slices.Sort(paths)
	return paths
}

// methodsOf reads the sorted method list out of an initialize result.
func methodsOf(t *testing.T, raw json.RawMessage) []string {
	t.Helper()
	var res struct{ Methods []string }
	decodeInto(t, raw, &res)
	return res.Methods
}

func contains(haystack string, needles ...string) string {
	for _, n := range needles {
		if strings.Contains(haystack, n) {
			return n
		}
	}
	return ""
}
