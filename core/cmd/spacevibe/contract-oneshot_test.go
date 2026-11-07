package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// homeEnv is the environment startCore gives a core on an empty home.
func homeEnv(home string) []string {
	return []string{
		"PATH=" + os.Getenv("PATH"), "HOME=" + home, "CLAUDE_CONFIG_DIR=" + filepath.Join(home, ".claude"),
		"CODEX_HOME=" + filepath.Join(home, ".codex"), "SPACEVIBE_HOME=" + filepath.Join(home, ".spacevibe"), "SPACEVIBE_TEST=1",
	}
}

// runBinary runs bin with args and exactly the environment env, and returns its output and exit code.
func runBinary(t *testing.T, bin string, env []string, args ...string) (stdout, stderr []byte, code int) {
	t.Helper()
	cmd := exec.Command(bin, args...)
	cmd.Env = env
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	err := cmd.Run()
	code = 0
	if err != nil {
		ee, ok := err.(*exec.ExitError)
		if !ok {
			t.Fatalf("%s %v: %v", bin, args, err)
		}
		code = ee.ExitCode()
	}
	return out.Bytes(), errOut.Bytes(), code
}

// oneShotCases are the contract cases of the `--json` commands (plan PR.3).
func oneShotCases(t *testing.T) {
	t.Run("one_shot_equals_rpc", func(t *testing.T) {
		home, data := sharedHome(t)
		env := append(append([]string{"PATH=" + os.Getenv("PATH")}, fixtureEnv(home)...), data...)
		c := startOn(t, shippedBin, home, data...)
		c.initialize()

		// The same object, byte for byte, as the RPC method returns it.
		for i, k := range []struct{ command, method, params string }{
			{"inventory", "inventory.read", `{}`},
			{"usage", "usage.scan", `{}`},
			{"limits", "limits.read", `{}`},
			{"rules", "rules.snapshot", `{"scope":"global","dir":null}`},
		} {
			id := string(rune('1' + i))
			c.send(request(id, k.method, k.params))
			var r reply
			for {
				line := c.recv()
				if !strings.Contains(line, `"method":"usage/progress"`) {
					r = parseReply(t, line)
					break
				}
			}
			out, errOut, code := runBinary(t, shippedBin, env, k.command, "--json")
			if code != 0 || len(errOut) != 0 {
				t.Fatalf("%s: exit %d, stderr %q", k.command, code, errOut)
			}
			if want := string(c.ok(r)) + "\n"; string(out) != want {
				t.Errorf("%s --json differs from %s:\n%.300s\n%.300s", k.command, k.method, out, want)
			}
		}
		// Activity moves with the clock, so compare it with the clock-driven members masked.
		rpcActivity := c.ok(c.call("9", "activity.read", `{}`))
		out, _, code := runBinary(t, shippedBin, env, "activity", "--json")
		if code != 0 || c.norm.line(strings.TrimSuffix(string(out), "\n")) != c.norm.line(string(rpcActivity)) {
			t.Errorf("activity --json (exit %d) differs from activity.read", code)
		}
		// Rules for a folder discovery did not find fall back to the global snapshot, as the RPC does.
		out, _, code = runBinary(t, shippedBin, env, "rules", "--json", "--dir", "/nowhere/at/all")
		var snap struct{ Scope string }
		if code != 0 || json.Unmarshal(out, &snap) != nil || snap.Scope != "global" {
			t.Errorf("rules --dir /nowhere/at/all: exit %d, %.200s", code, out)
		}
		c.finish("one_shot_equals_rpc")
	})

	t.Run("one_shot_json_pipes", func(t *testing.T) {
		python, err := exec.LookPath("python3")
		if err != nil {
			t.Skip("python3 not found")
		}
		home, data := sharedHome(t)
		env := append(append([]string{"PATH=" + os.Getenv("PATH")}, fixtureEnv(home)...), data...)
		act := exec.Command(shippedBin, "activity", "--json")
		act.Env = env
		tool := exec.Command(python, "-I", "-m", "json.tool")
		pipe, err := act.StdoutPipe()
		if err != nil {
			t.Fatal(err)
		}
		tool.Stdin = pipe
		var toolErr bytes.Buffer
		tool.Stderr = &toolErr
		if err := act.Start(); err != nil {
			t.Fatal(err)
		}
		if err := tool.Run(); err != nil {
			t.Fatalf("python3 -m json.tool: %v %s", err, toolErr.String())
		}
		if err := act.Wait(); err != nil {
			t.Fatalf("activity --json: %v", err)
		}
	})

	t.Run("one_shot_exit_codes", func(t *testing.T) {
		home := t.TempDir()
		env := homeEnv(home)
		for _, tc := range []struct {
			args     []string
			env      []string
			code     int
			errWords string
		}{
			{[]string{"inventory"}, env, 2, "usage:"},
			{[]string{"inventory", "--json", "--extra"}, env, 2, "usage:"},
			{[]string{"activity", "--json", "--dir", "/x"}, env, 2, "usage:"},
			{[]string{"rules", "--json", "--dir"}, env, 2, "usage:"},
			{[]string{"rules", "--json", "--dir", "relative/dir"}, env, 1, "absolute"},
			{[]string{"inventory", "--json"}, append(append([]string{}, env...), "SPACEVIBE_TEST=banana"), 1, "SPACEVIBE_TEST"},
			{[]string{"inventory", "--json"}, env, 0, ""},
			{[]string{"limits", "--json"}, env, 0, ""},
		} {
			out, errOut, code := runBinary(t, shippedBin, tc.env, tc.args...)
			if code != tc.code {
				t.Errorf("%v: exit %d, want %d (stderr %q)", tc.args, code, tc.code, errOut)
			}
			if tc.code != 0 && len(out) != 0 {
				t.Errorf("%v: failed but printed %q", tc.args, out)
			}
			if tc.code == 0 && (len(errOut) != 0 || !json.Valid(out)) {
				t.Errorf("%v: exit 0 with stderr %q or bad JSON", tc.args, errOut)
			}
			if !strings.Contains(string(errOut), tc.errWords) {
				t.Errorf("%v: stderr %q lacks %q", tc.args, errOut, tc.errWords)
			}
		}
	})
}
