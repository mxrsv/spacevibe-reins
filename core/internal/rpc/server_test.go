package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
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
