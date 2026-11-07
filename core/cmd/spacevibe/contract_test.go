package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/rpc"
)

// TestContract runs the built binary over stdio. Each case is one subtest and writes its
// conversation to core/testdata/rpc/<case>.jsonl (-update rewrites them).
func TestContract(t *testing.T) {
	t.Run("handshake_ok", func(t *testing.T) {
		c := startCore(t, debugBin)
		r := c.initialize()
		var res struct {
			ProtocolVersion int `json:"protocolVersion"`
			Core            struct{ Name, Version string }
			Identity        struct{ EnvPrefix, DataDir string }
			Methods         []string
		}
		if err := json.Unmarshal(r.Result, &res); err != nil {
			t.Fatal(err)
		}
		if res.ProtocolVersion != 1 || res.Core.Name != "spacevibe" || res.Core.Version == "" ||
			res.Identity.EnvPrefix != "SPACEVIBE_" || res.Identity.DataDir != ".spacevibe" {
			t.Fatalf("bad result: %s", r.Result)
		}
		if !slices.Contains(res.Methods, "initialize") || !slices.IsSorted(res.Methods) {
			t.Fatalf("methods: %v", res.Methods)
		}
		for _, m := range res.Methods {
			if !slices.Contains(rpc.AllMethods, m) && !strings.HasPrefix(m, "debug.") {
				t.Fatalf("method %q is neither in AllMethods nor a debug method", m)
			}
		}
		if r := c.call("1", "debug.slow", `{"ms":0}`); r.Error != nil {
			t.Fatalf("request after initialize: %+v", r.Error)
		}
		c.finish("handshake_ok")
	})

	t.Run("version_mismatch_refused", func(t *testing.T) {
		c := startCore(t, debugBin)
		for _, v := range []string{`2`, `"1"`, `0`} {
			r := c.call("1", "initialize", `{"protocolVersion":`+v+`,"client":{"name":"c","version":"0"},"future":true}`)
			c.wantError(r, -32001)
			if string(r.Error.Data) != `{"protocolVersion":1}` {
				t.Fatalf("data: %s", r.Error.Data)
			}
		}
		c.wantError(c.call("2", "debug.slow", `{"ms":0}`), -32002) // still not initialized
		c.finish("version_mismatch_refused")
	})

	t.Run("request_before_initialize", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.wantError(c.call("1", "debug.slow", `{"ms":0}`), -32002)
		c.wantError(c.call("2", "no.such.method", ""), -32002)
		c.send(`{"jsonrpc":"2.0","method":"debug.slow","params":{"ms":0}}`) // notification: dropped
		c.send(`{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":1}}`)
		c.expectNone(200 * time.Millisecond)
		c.initialize()
		c.wantError(c.call("3", "initialize", `{"protocolVersion":1}`), -32600) // a second initialize
		c.finish("request_before_initialize")
	})

	t.Run("unknown_method", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		c.wantError(c.call(`"req-7"`, "no.such.method", ""), -32601)
		c.wantError(c.call("2", "debug.slow", `{"mss":1}`), -32602)
		c.finish("unknown_method")
	})

	t.Run("parse_error_continues", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		c.send(`{"jsonrpc":"2.0","id":1,"method":`)
		r := parseReply(t, c.recv())
		c.wantError(r, -32700)
		if string(r.ID) != "null" {
			t.Fatalf("id %s, want null", r.ID)
		}
		c.send("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"\xff\"}") // invalid UTF-8
		c.wantError(parseReply(t, c.recv()), -32700)
		c.send(``) // a blank line is skipped
		c.send(`"just a string"`)
		c.wantError(parseReply(t, c.recv()), -32600)
		c.send(`{"jsonrpc":"2.0","id":1.5,"method":"x"}`)
		c.wantError(parseReply(t, c.recv()), -32600)
		if r := c.call("3", "debug.slow", `{"ms":0}`); r.Error != nil {
			t.Fatalf("stream did not continue: %+v", r.Error)
		}
		c.finish("parse_error_continues")
	})

	t.Run("oversized_line", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		// Exactly the cap is accepted: a request whose method name pads it to 1 MiB.
		head, tail := `{"jsonrpc":"2.0","id":9,"method":"`, `"}`
		exact := head + strings.Repeat("m", rpc.MaxRequestLine-len(head)-len(tail)) + tail
		c.send(exact)
		r := parseReply(t, c.recv())
		c.wantError(r, -32601)
		if string(r.ID) != "9" {
			t.Fatalf("id %s", r.ID)
		}
		// One byte over is discarded through its newline and answered with id null.
		c.send(exact + " ")
		r = parseReply(t, c.recv())
		c.wantError(r, -32600)
		if string(r.ID) != "null" {
			t.Fatalf("id %s", r.ID)
		}
		c.send(strings.Repeat("x", 3*rpc.MaxRequestLine)) // many buffer refills, still one answer
		c.wantError(parseReply(t, c.recv()), -32600)
		if r := c.call("10", "debug.slow", `{"ms":0}`); r.Error != nil {
			t.Fatalf("stream did not continue: %+v", r.Error)
		}
		c.finish("oversized_line")
	})

	t.Run("batch_refused", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		c.send(`[` + request("1", "debug.slow", `{"ms":0}`) + `]`)
		r := parseReply(t, c.recv())
		c.wantError(r, -32600)
		if string(r.ID) != "null" {
			t.Fatalf("id %s", r.ID)
		}
		c.send(`[]`)
		c.wantError(parseReply(t, c.recv()), -32600)
		c.finish("batch_refused")
	})

	t.Run("cancel_request", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		c.send(request("5", "debug.slow", `{"ms":60000}`))
		c.send(`{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":5}}`)
		c.wantError(c.reply("5"), -32800)
		// A started write ignores the cancel: its real result comes back.
		c.send(request("6", "debug.slow", `{"ms":300,"uncancellable":true}`))
		c.send(`{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":6}}`)
		if r := c.reply("6"); r.Error != nil || string(r.Result) != `{"slept":true}` {
			t.Fatalf("got %+v %s", r.Error, r.Result)
		}
		// An unknown or finished id is ignored.
		c.send(`{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":5}}`)
		c.send(`{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":"nope"}}`)
		c.send(`{"jsonrpc":"2.0","method":"$/cancelRequest","params":7}`)
		if r := c.call("7", "debug.slow", `{"ms":0}`); r.Error != nil {
			t.Fatalf("%+v", r.Error)
		}
		c.finish("cancel_request")
	})

	t.Run("concurrent_requests", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		c.send(request("1", "debug.slow", `{"ms":600}`))
		c.send(request(`"fast-a"`, "debug.slow", `{"ms":0}`))
		c.reply(`"fast-a"`)
		c.send(request("3", "debug.slow", `{"ms":0}`))
		c.reply("3")
		c.send(request("3", "debug.slow", `{"ms":0}`)) // id 3 finished, so it can be reused
		c.reply("3")
		c.reply("1") // the slow one answers last
		c.finish("concurrent_requests")
	})

	t.Run("stray_print_on_stderr", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		r := c.call("1", "debug.print", "")
		if string(r.Result) != `{"printed":true}` {
			t.Fatalf("%+v %s", r.Error, r.Result)
		}
		if r := c.call("2", "debug.slow", `{"ms":0}`); r.Error != nil {
			t.Fatal("stream corrupted after a stray print")
		}
		c.finish("stray_print_on_stderr") // fails on any stdout line that is not a reply we read
		want := []string{"stray-println", "stray-os-stdout"}
		if runtime.GOOS == "darwin" {
			want = append(want, "stray-fd1")
		}
		for _, w := range want {
			if !strings.Contains(c.stderr.String(), w) {
				t.Errorf("stderr lacks %q: %q", w, c.stderr.String())
			}
		}
	})

	t.Run("panic_recovered", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		r := c.call("1", "debug.panic", "")
		c.wantError(r, -32603)
		if r.Error.Message != "Internal error." {
			t.Fatalf("message %q", r.Error.Message)
		}
		if r := c.call("2", "debug.slow", `{"ms":0}`); r.Error != nil {
			t.Fatal("the core did not survive the panic")
		}
		c.finish("panic_recovered")
		if strings.Contains(c.stderr.String(), "SECRET-PANIC-VALUE") {
			t.Error("stderr repeats the panic value")
		}
		if !strings.Contains(c.stderr.String(), "panic in debug.panic") {
			t.Errorf("stderr does not name the panic: %q", c.stderr.String())
		}
	})

	t.Run("startup_problem", func(t *testing.T) {
		c := startCore(t, debugBin, "SPACEVIBE_TEST=banana")
		c.initialize() // still succeeds
		r := c.call("1", "debug.slow", `{"ms":0}`)
		c.wantError(r, -32000)
		if !strings.Contains(r.Error.Message, "SPACEVIBE_TEST") ||
			string(r.Error.Data) != `{"status":500,"message":`+strconv.Quote(r.Error.Message)+`}` {
			t.Fatalf("got %+v", r.Error)
		}
		c.wantError(c.call("2", "no.such.method", ""), -32601)
		for i, m := range []string{"inventory.read", "usage.scan", "rules.add", "journal.undo", "activity.subscribe"} { // every domain method
			if got := c.status(c.call(strconv.Itoa(3+i), m, `{}`)); got != 500 {
				t.Errorf("%s: status %d", m, got)
			}
		}
		c.finish("startup_problem")
	})

	t.Run("shipped_binary_has_no_debug_methods", func(t *testing.T) {
		c := startCore(t, shippedBin)
		var res struct{ Methods []string }
		if err := json.Unmarshal(c.initialize().Result, &res); err != nil {
			t.Fatal(err)
		}
		if want := slices.Sorted(slices.Values(rpc.AllMethods)); !slices.Equal(res.Methods, want) {
			t.Fatalf("methods: %v, want exactly AllMethods %v", res.Methods, want)
		}
		c.wantError(c.call("1", "debug.print", ""), -32601)
		c.finish("shipped_binary")
	})

	t.Run("eof_exits_zero", func(t *testing.T) {
		c := startCore(t, debugBin)
		c.initialize()
		c.call("1", "debug.slow", `{"ms":0}`)
		c.finish("eof_exits_zero")
		var left []string
		filepath.WalkDir(c.home, func(p string, d os.DirEntry, _ error) error {
			if ok, _ := filepath.Match("*.spacevibe-*.tmp", d.Name()); ok {
				left = append(left, p)
			}
			return nil
		})
		if len(left) != 0 {
			t.Fatalf("temp files left: %v", left)
		}

		// A request that ignores cancel is abandoned after the 5 s drain; exit is still 0.
		c = startCore(t, debugBin)
		c.initialize()
		c.send(request("1", "debug.slow", `{"ms":60000,"uncancellable":true}`))
		c.call("2", "debug.slow", `{"ms":0}`) // the reader has passed request 1
		begin := time.Now()
		if code := c.waitExit(true); code != 0 {
			t.Fatalf("exit %d, stderr: %s", code, c.stderr.String())
		}
		if d := time.Since(begin); d < 4*time.Second {
			t.Fatalf("exited after %v: the drain did not wait for the running request", d)
		}
		if !strings.Contains(c.stderr.String(), "drain timeout") {
			t.Errorf("stderr: %q", c.stderr.String())
		}
	})

	t.Run("no_listener", func(t *testing.T) {
		if runtime.GOOS != "darwin" {
			t.Skip("lsof check is darwin only")
		}
		lsof, err := exec.LookPath("lsof")
		if err != nil {
			t.Skip("lsof not found")
		}
		c := startCore(t, debugBin)
		c.initialize()
		out, _ := exec.Command(lsof, "-nP", "-a", "-p", strconv.Itoa(c.cmd.Process.Pid), "-i").Output() // exit 1 means nothing found
		if strings.TrimSpace(string(out)) != "" {
			t.Fatalf("the core holds network files:\n%s", out)
		}
		c.finish("no_listener")
	})

	readCases(t)
	writeCases(t)
	leakCases(t)
	oneShotCases(t)

	t.Run("no_net_deps", func(t *testing.T) {
		for _, tags := range []string{"", "contracttest"} {
			cmd := exec.Command("go", "list", "-deps", "-tags", tags, ".")
			cmd.Env = append(os.Environ(), "CGO_ENABLED=0")
			out, err := cmd.Output()
			if err != nil {
				t.Fatal(err)
			}
			for _, pkg := range strings.Fields(string(out)) {
				if pkg == "net" || pkg == "net/http" || pkg == "crypto/tls" {
					t.Errorf("tags %q: the core imports %s (S-R5)", tags, pkg)
				}
			}
		}
	})
}
