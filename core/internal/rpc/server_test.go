package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/coreerr"
)

const initLine = `{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":1,"client":{"name":"t","version":"0"}}}` + "\n"

// session runs input through a server whose registry has extra handlers and returns the output
// lines and the log.
func session(t *testing.T, opts Options, register func(*Registry), input string) ([]string, string) {
	t.Helper()
	var logbuf, out bytes.Buffer
	opts.Log = &logbuf
	reg := NewRegistry()
	register(reg)
	srv := NewServer(reg, opts)
	if err := srv.Serve(context.Background(), strings.NewReader(input), &out); err != nil {
		t.Fatal(err)
	}
	return strings.Split(strings.TrimSuffix(out.String(), "\n"), "\n"), logbuf.String()
}

func TestResultTooLargeAndPanicAndEngineError(t *testing.T) {
	big := strings.Repeat("a", MaxResponseLine)
	lines, log := session(t, Options{}, func(r *Registry) {
		r.Register("t.big", func(context.Context, Call) (any, error) { return big, nil })
		r.Register("t.panic", func(context.Context, Call) (any, error) { panic("SECRET-CONTENT") })
		r.Register("t.engine", func(context.Context, Call) (any, error) {
			return nil, coreerr.NewStatus("Nothing to change.", coreerr.StatusConflict)
		})
		r.Register("t.plain", func(context.Context, Call) (any, error) { return nil, errors.New("SECRET-CONTENT") })
	}, initLine+
		`{"jsonrpc":"2.0","id":1,"method":"t.big"}`+"\n"+
		`{"jsonrpc":"2.0","id":2,"method":"t.panic"}`+"\n"+
		`{"jsonrpc":"2.0","id":3,"method":"t.engine"}`+"\n"+
		`{"jsonrpc":"2.0","id":4,"method":"t.plain"}`+"\n")
	got := map[string]string{}
	for _, l := range lines {
		var m struct {
			ID json.RawMessage `json:"id"`
		}
		_ = json.Unmarshal([]byte(l), &m)
		got[string(m.ID)] = l
	}
	want := map[string]string{
		"1": `{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"The result is too large.","data":{"status":413,"message":"The result is too large."}}}`,
		"2": `{"jsonrpc":"2.0","id":2,"error":{"code":-32603,"message":"Internal error."}}`,
		"3": `{"jsonrpc":"2.0","id":3,"error":{"code":-32000,"message":"Nothing to change.","data":{"status":409,"message":"Nothing to change."}}}`,
		"4": `{"jsonrpc":"2.0","id":4,"error":{"code":-32603,"message":"Internal error."}}`,
	}
	for id, w := range want {
		if got[id] != w {
			t.Errorf("id %s:\n got %s\nwant %s", id, got[id], w)
		}
	}
	if strings.Contains(log, "SECRET-CONTENT") {
		t.Error("the log quotes the panic value")
	}
	if !strings.Contains(log, "panic in t.panic") {
		t.Errorf("the log does not name the panic: %q", log)
	}
}

func TestDrainTimeoutAbandonsStuckRequest(t *testing.T) {
	release := make(chan struct{})
	defer close(release)
	start := time.Now()
	_, log := session(t, Options{DrainTimeout: 150 * time.Millisecond}, func(r *Registry) {
		r.Register("t.stuck", func(context.Context, Call) (any, error) { <-release; return nil, nil })
	}, initLine+`{"jsonrpc":"2.0","id":1,"method":"t.stuck"}`+"\n")
	if d := time.Since(start); d > 3*time.Second {
		t.Fatalf("Serve took %v", d)
	}
	if !strings.Contains(log, "drain timeout") {
		t.Fatalf("no drain timeout in log: %q", log)
	}
}

func TestDecodeParams(t *testing.T) {
	type p struct {
		Verdict string `json:"verdict"`
		N       int    `json:"n"`
	}
	cases := []struct {
		name, in, want string // want is the error message, "" for success
	}{
		{"empty", ``, ""},
		{"null", `null`, ""},
		{"ok", `{"verdict":"allow","n":1}`, ""},
		{"unknown member", `{"verdct":"SECRET"}`, `Invalid params: "verdct" is not a known member.`},
		{"wrong type", `{"n":"SECRET"}`, `Invalid params: n has the wrong type.`},
		{"array", `[1]`, `Invalid params: params must be an object.`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var v p
			err := DecodeParams(json.RawMessage(c.in), &v)
			if c.want == "" {
				if err != nil {
					t.Fatal(err)
				}
				return
			}
			var re *Error
			if !errors.As(err, &re) || re.Code != CodeInvalidParams || re.Message != c.want {
				t.Fatalf("got %v, want -32602 %q", err, c.want)
			}
			if strings.Contains(re.Message, "SECRET") {
				t.Fatal("message quotes a value")
			}
		})
	}
}

// Call.Session is alive while input flows and cancelled when it ends, before the drain: a poll started from a
// handler stops at end of input.
func TestCallSessionEndsWithInput(t *testing.T) {
	reg := NewRegistry()
	got := make(chan context.Context, 1)
	reg.Register("t.hold", func(_ context.Context, call Call) (any, error) {
		got <- call.Session
		return struct{}{}, nil
	})
	srv := NewServer(reg, Options{})
	in, feed := io.Pipe()
	var out bytes.Buffer
	done := make(chan struct{})
	go func() { _ = srv.Serve(context.Background(), in, &out); close(done) }()
	io.WriteString(feed, initLine+`{"jsonrpc":"2.0","id":1,"method":"t.hold"}`+"\n")
	var session context.Context
	select {
	case session = <-got:
	case <-time.After(5 * time.Second):
		t.Fatal("the handler did not run")
	}
	if session == nil || session.Err() != nil {
		t.Fatalf("session %v while input is open", session)
	}
	feed.Close()
	select {
	case <-session.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the session context was not cancelled at end of input")
	}
	<-done
}

// lineChan is an output whose every Write (the server writes one whole line at a time) lands on a channel.
type lineChan chan string

func (c lineChan) Write(b []byte) (int, error) { c <- string(b); return len(b), nil }

func startPipeServer(t *testing.T, register func(*Registry)) (srv *Server, feed *io.PipeWriter, lines lineChan) {
	t.Helper()
	reg := NewRegistry()
	register(reg)
	srv = NewServer(reg, Options{})
	in, feed := io.Pipe()
	lines = make(lineChan, 1024)
	done := make(chan struct{})
	go func() { _ = srv.Serve(context.Background(), in, lines); close(done) }()
	t.Cleanup(func() { feed.Close(); <-done })
	io.WriteString(feed, initLine)
	if l := nextLine(t, lines); !strings.Contains(l, `"id":0`) {
		t.Fatalf("initialize reply %q", l)
	}
	return srv, feed, lines
}

func nextLine(t *testing.T, lines lineChan) string {
	t.Helper()
	select {
	case l := <-lines:
		return l
	case <-time.After(5 * time.Second):
		t.Fatal("no reply")
		return ""
	}
}

// The id of a request is free again before its reply leaves, so a client that reuses the id right after the answer
// never meets a spurious "already in use" (-32600). Held here by taking the server's lock while the handler returns:
// the reply must wait for the release.
func TestInflightIDIsReleasedBeforeTheReply(t *testing.T) {
	started := make(chan struct{})
	gate := make(chan struct{})
	srv, feed, lines := startPipeServer(t, func(r *Registry) {
		r.Register("t.gate", func(context.Context, Call) (any, error) { close(started); <-gate; return "ok", nil })
	})
	io.WriteString(feed, `{"jsonrpc":"2.0","id":1,"method":"t.gate"}`+"\n")
	<-started
	srv.mu.Lock()
	close(gate)
	select {
	case l := <-lines:
		srv.mu.Unlock()
		t.Fatalf("replied while the id was still registered: %s", l)
	case <-time.After(200 * time.Millisecond):
	}
	srv.mu.Unlock()
	if l := nextLine(t, lines); !strings.Contains(l, `"result":"ok"`) {
		t.Fatalf("reply %s", l)
	}
}

func TestClientMayReuseAnIDRightAfterTheAnswer(t *testing.T) {
	_, feed, lines := startPipeServer(t, func(r *Registry) {
		r.Register("t.echo", func(context.Context, Call) (any, error) { return "ok", nil })
	})
	for i := 0; i < 500; i++ {
		io.WriteString(feed, `{"jsonrpc":"2.0","id":7,"method":"t.echo"}`+"\n")
		if l := nextLine(t, lines); !strings.Contains(l, `"result":"ok"`) {
			t.Fatalf("round %d: %s", i, l)
		}
	}
}

// brokenLog is a log whose reader has gone: every write fails.
type brokenLog struct{}

func (brokenLog) Write([]byte) (int, error) { return 0, errors.New("write: broken pipe") }

// A log that cannot be written never stops the server: the request that logged still gets its answer, and so does
// the next one.
func TestServerSurvivesALogThatFails(t *testing.T) {
	reg := NewRegistry()
	reg.Register("t.panic", func(context.Context, Call) (any, error) { panic("x") })
	reg.Register("t.ok", func(context.Context, Call) (any, error) { return true, nil })
	var out bytes.Buffer
	srv := NewServer(reg, Options{Log: brokenLog{}})
	input := initLine +
		`{"jsonrpc":"2.0","id":1,"method":"t.panic"}` + "\n" +
		`{"jsonrpc":"2.0","id":2,"method":"t.ok"}` + "\n"
	if err := srv.Serve(context.Background(), strings.NewReader(input), &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), `"id":1,"error":{"code":-32603`) || !strings.Contains(out.String(), `"id":2,"result":true`) {
		t.Errorf("output %q", out.String())
	}
}
