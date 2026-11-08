package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

var update = flag.Bool("update", false, "rewrite core/testdata/rpc/*.jsonl")

const (
	recvTimeout = 10 * time.Second
	exitTimeout = 6 * time.Second
	transcripts = "../../testdata/rpc"
)

var shippedBin, debugBin string // the binary as shipped, and the one built with -tags contracttest

func TestMain(m *testing.M) {
	flag.Parse()
	dir, err := os.MkdirTemp("", "spacevibe-contract-")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	build := func(out string, args ...string) string {
		path := filepath.Join(dir, out)
		cmd := exec.Command("go", append([]string{"build", "-o", path}, append(args, ".")...)...)
		cmd.Env = append(os.Environ(), "CGO_ENABLED=0")
		if b, err := cmd.CombinedOutput(); err != nil {
			fmt.Fprintf(os.Stderr, "build failed: %v\n%s", err, b)
			os.RemoveAll(dir)
			os.Exit(1)
		}
		return path
	}
	shippedBin = build("spacevibe")
	debugBin = build("spacevibe-contracttest", "-tags", "contracttest")
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

type lockedBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *lockedBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}
func (l *lockedBuffer) String() string { l.mu.Lock(); defer l.mu.Unlock(); return l.b.String() }

// core is one running binary with a recorded conversation.
type core struct {
	t      *testing.T
	cmd    *exec.Cmd
	stdin  io.WriteCloser
	pw     *io.PipeWriter
	pr     *io.PipeReader
	lines  chan string
	stderr lockedBuffer
	home   string
	rec    []recorded
	done   chan error
	// norm, when set, rewrites every recorded line before it is compared with the transcript (see normalize.go).
	norm  *normalizer
	start time.Time
}

// startCore runs bin with a synthetic, empty home. env entries (KEY=value) override the defaults.
func startCore(t *testing.T, bin string, env ...string) *core {
	t.Helper()
	return startCoreIn(t, bin, t.TempDir(), env...)
}

// startCoreIn runs bin with its roots under home. env entries (KEY=value) override the defaults.
func startCoreIn(t *testing.T, bin, home string, env ...string) *core {
	t.Helper()
	c := prepareCoreIn(t, bin, home, env...)
	c.begin()
	return c
}

// prepareCoreIn builds the core's command without starting it, so a test can change its wiring first.
func prepareCoreIn(t *testing.T, bin, home string, env ...string) *core {
	t.Helper()
	vars := map[string]string{
		"PATH": os.Getenv("PATH"), "HOME": home,
		"CLAUDE_CONFIG_DIR": filepath.Join(home, ".claude"), "CODEX_HOME": filepath.Join(home, ".codex"),
		"SPACEVIBE_HOME": filepath.Join(home, ".spacevibe"), "SPACEVIBE_TEST": "1",
	}
	for _, e := range env {
		k, v, _ := strings.Cut(e, "=")
		vars[k] = v
	}
	c := &core{t: t, home: home, lines: make(chan string, 1024), done: make(chan error, 1)}
	c.cmd = exec.Command(bin, "rpc")
	for k, v := range vars {
		c.cmd.Env = append(c.cmd.Env, k+"="+v)
	}
	pr, pw := io.Pipe()
	c.pw = pw
	c.cmd.Stdout = pw
	c.cmd.Stderr = &c.stderr
	var err error
	if c.stdin, err = c.cmd.StdinPipe(); err != nil {
		t.Fatal(err)
	}
	c.pr = pr
	return c
}

// begin starts the prepared command and the goroutines that read its output.
func (c *core) begin() {
	t, pr, pw := c.t, c.pr, c.pw
	if err := c.cmd.Start(); err != nil {
		t.Fatal(err)
	}
	c.start = time.Now()
	go func() {
		rd := bufio.NewReaderSize(pr, 1<<20)
		for {
			line, err := rd.ReadString('\n')
			if line != "" {
				c.lines <- strings.TrimSuffix(line, "\n")
			}
			if err != nil {
				close(c.lines)
				return
			}
		}
	}()
	go func() { err := c.cmd.Wait(); pw.Close(); c.done <- err }()
	t.Cleanup(func() { c.cmd.Process.Kill() })
}

type transcriptLine struct {
	Dir  string          `json:"dir"`
	JSON json.RawMessage `json:"json,omitempty"`
	Text string          `json:"text,omitempty"`
}

// recorded is one line of the conversation as it went over the wire.
type recorded struct{ dir, line string }

func (c *core) record(dir, line string) { c.rec = append(c.rec, recorded{dir, line}) }

// transcript renders the conversation as the JSON lines of core/testdata/rpc.
func (c *core) transcript() string {
	out := make([]string, 0, len(c.rec))
	for _, r := range c.rec {
		line := r.line
		if c.norm != nil {
			line = c.norm.line(line)
		}
		tl := transcriptLine{Dir: r.dir}
		switch {
		case len(line) <= 2048 && json.Valid([]byte(line)):
			tl.JSON = json.RawMessage(line)
		case len(line) <= 2048:
			tl.Text = line
		default:
			tl.Text = fmt.Sprintf("(%d bytes)", len(line))
		}
		b, _ := json.Marshal(tl)
		out = append(out, string(b))
	}
	return strings.Join(out, "\n") + "\n"
}

// send writes one line (a newline is added).
func (c *core) send(line string) {
	c.t.Helper()
	c.record("send", line)
	if _, err := io.WriteString(c.stdin, line+"\n"); err != nil {
		c.t.Fatalf("write: %v", err)
	}
}

// recv returns the next output line.
func (c *core) recv() string {
	c.t.Helper()
	select {
	case l, ok := <-c.lines:
		if !ok {
			c.t.Fatal("stdout closed while waiting for a line")
		}
		c.record("recv", l)
		return l
	case <-time.After(recvTimeout):
		c.t.Fatal("timed out waiting for a line")
	}
	return ""
}

// expectNone fails if a line arrives within d.
func (c *core) expectNone(d time.Duration) {
	c.t.Helper()
	select {
	case l := <-c.lines:
		c.t.Fatalf("unexpected line: %.200s", l)
	case <-time.After(d):
	}
}

type reply struct {
	ID     json.RawMessage `json:"id"`
	Result json.RawMessage `json:"result"`
	Error  *struct {
		Code    int             `json:"code"`
		Message string          `json:"message"`
		Data    json.RawMessage `json:"data"`
	} `json:"error"`
}

func parseReply(t *testing.T, line string) reply {
	t.Helper()
	var r reply
	if err := json.Unmarshal([]byte(line), &r); err != nil {
		t.Fatalf("not a JSON line: %.200q", line)
	}
	return r
}

// call sends a request and returns its reply, which must carry the same id.
func (c *core) call(id, method, params string) reply {
	c.t.Helper()
	c.send(request(id, method, params))
	return c.reply(id)
}

// reply reads the next line and checks its id.
func (c *core) reply(id string) reply {
	c.t.Helper()
	r := parseReply(c.t, c.recv())
	if string(r.ID) != id {
		c.t.Fatalf("reply id %s, want %s", r.ID, id)
	}
	return r
}

func request(id, method, params string) string {
	s := `{"jsonrpc":"2.0","id":` + id + `,"method":"` + method + `"`
	if params != "" {
		s += `,"params":` + params
	}
	return s + `}`
}

func (c *core) initialize() reply {
	c.t.Helper()
	r := c.call("0", "initialize", `{"protocolVersion":1,"client":{"name":"contract","version":"0"}}`)
	if r.Error != nil {
		c.t.Fatalf("initialize failed: %+v", r.Error)
	}
	return r
}

func (c *core) wantError(r reply, code int) {
	c.t.Helper()
	if r.Error == nil || r.Error.Code != code {
		c.t.Fatalf("got %+v / %s, want error %d", r.Error, r.Result, code)
	}
}

// waitExit closes stdin if asked, waits up to exitTimeout and returns the exit code.
func (c *core) waitExit(closeStdin bool) int {
	c.t.Helper()
	if closeStdin {
		c.stdin.Close()
	}
	select {
	case <-c.done:
		return c.cmd.ProcessState.ExitCode()
	case <-time.After(exitTimeout):
		c.cmd.Process.Kill()
		c.t.Fatalf("the core did not exit within %v of EOF", exitTimeout)
	}
	return -1
}

// finish ends the session cleanly (exit 0, no stray stdout) and checks the transcript.
func (c *core) finish(name string) {
	c.t.Helper()
	c.end()
	c.checkTranscript(name)
}

// end is finish without the transcript, for a case whose interleaving of notifications is not fixed.
func (c *core) end() {
	c.t.Helper()
	if code := c.waitExit(true); code != 0 {
		c.t.Fatalf("exit code %d, stderr: %s", code, c.stderr.String())
	}
	for l := range c.lines {
		c.t.Fatalf("unexpected output after the session: %.200q", l)
	}
}

func (c *core) checkTranscript(name string) {
	c.t.Helper()
	got := c.transcript()
	path := filepath.Join(transcripts, name+".jsonl")
	if *update {
		if err := os.MkdirAll(transcripts, 0o755); err != nil {
			c.t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			c.t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(path)
	if err != nil {
		c.t.Fatalf("no transcript %s (run with -update): %v", path, err)
	}
	if string(want) != got {
		c.t.Fatalf("transcript %s differs (run with -update to accept):\n--- want\n%s--- got\n%s", path, want, got)
	}
}
