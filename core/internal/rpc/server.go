package rpc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"runtime/debug"
	"sync"
	"time"
	"unicode/utf8"
)

// DefaultDrainTimeout is how long in-flight requests get to finish after stdin closes.
const DefaultDrainTimeout = 5 * time.Second

// Options configure a Server.
type Options struct {
	// StartupProblem is a fixed sentence. When set, `initialize` still succeeds so the shell learns
	// the identity, and every other known method fails with -32000, status 500 and this sentence.
	StartupProblem string
	// DrainTimeout bounds the wait for in-flight requests at end of input. Zero means DefaultDrainTimeout.
	DrainTimeout time.Duration
	// Log receives one line per event. Fixed reasons only: no params, no file content. Nil discards.
	Log io.Writer
}

// Server speaks the protocol on one connection. Build it with NewServer; call Serve once.
type Server struct {
	reg  *Registry
	opts Options

	initialized bool // touched only by the reading goroutine

	mu       sync.Mutex
	inflight map[string]context.CancelFunc

	wg         sync.WaitGroup
	out        chan []byte
	stop       chan struct{}
	writerDone chan struct{}
}

// NewServer returns a server over reg and registers `initialize` on it.
func NewServer(reg *Registry, opts Options) *Server {
	if opts.DrainTimeout <= 0 {
		opts.DrainTimeout = DefaultDrainTimeout
	}
	if opts.Log == nil {
		opts.Log = io.Discard
	}
	s := &Server{
		reg:        reg,
		opts:       opts,
		inflight:   map[string]context.CancelFunc{},
		out:        make(chan []byte, 64),
		stop:       make(chan struct{}),
		writerDone: make(chan struct{}),
	}
	reg.Register(MethodInitialize, s.initialize)
	return s
}

// Serve reads requests from in and writes responses to out until in ends, then waits at most
// DrainTimeout for running requests and returns. It returns nil at a clean end of input and the
// read error otherwise. One goroutine owns out. A blocked read cannot be interrupted, so ctx only
// reaches the handlers.
func (s *Server) Serve(ctx context.Context, in io.Reader, out io.Writer) error {
	go s.writeLoop(out)
	rctx, cancelAll := context.WithCancel(ctx)
	defer cancelAll()

	readErr := s.readLoop(rctx, in)

	cancelAll()
	done := make(chan struct{})
	go func() { s.wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(s.opts.DrainTimeout):
		s.logf("drain timeout: abandoning running requests")
	}
	close(s.stop)
	<-s.writerDone
	return readErr
}

func (s *Server) readLoop(ctx context.Context, in io.Reader) error {
	lr := newLineReader(in)
	for {
		line, tooLong, err := lr.next(MaxRequestLine)
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if tooLong {
			s.reply(nil, nil, newError(CodeInvalidRequest, "The request line is too large."))
			continue
		}
		s.handleLine(ctx, line)
	}
}

// request holds each member raw, so a wrong type is reported as an invalid request, never lost.
type request struct {
	JSONRPC json.RawMessage `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  json.RawMessage `json:"method"`
	Params  json.RawMessage `json:"params"`
}

func (s *Server) handleLine(ctx context.Context, line []byte) {
	trimmed := bytes.TrimSpace(line)
	if len(trimmed) == 0 {
		return
	}
	if !utf8.Valid(trimmed) || !json.Valid(trimmed) {
		s.reply(nil, nil, newError(CodeParse, "Parse error."))
		return
	}
	switch trimmed[0] {
	case '[':
		s.reply(nil, nil, newError(CodeInvalidRequest, "Batch requests are not supported."))
		return
	case '{':
	default:
		s.reply(nil, nil, newError(CodeInvalidRequest, "Invalid request."))
		return
	}
	var req request
	_ = json.Unmarshal(trimmed, &req) // cannot fail: members are raw and the line is valid JSON

	hasID := len(req.ID) > 0
	validID := hasID && validID(req.ID)
	var replyID json.RawMessage
	if validID {
		replyID = req.ID
	}
	var method string
	if string(req.JSONRPC) != `"2.0"` || json.Unmarshal(req.Method, &method) != nil || method == "" || (hasID && !validID) {
		s.reply(replyID, nil, newError(CodeInvalidRequest, "Invalid request."))
		return
	}

	if !hasID { // notification: never answered
		if method == MethodCancel && s.initialized {
			s.cancel(req.Params)
		}
		return
	}
	switch {
	case method == MethodInitialize && s.initialized:
		s.reply(req.ID, nil, newError(CodeInvalidRequest, "The session is already initialized."))
		return
	case method != MethodInitialize && !s.initialized:
		s.reply(req.ID, nil, newError(CodeNotInitialized, "Send initialize first."))
		return
	}
	h, ok := s.reg.lookup(method)
	if !ok {
		s.reply(req.ID, nil, newError(CodeMethodNotFound, "Method not found."))
		return
	}
	call := Call{ID: req.ID, Params: req.Params, Session: ctx, notify: s.notify}
	if method == MethodInitialize { // inline: the next line must see the session state
		res, err := s.invoke(ctx, method, h, call)
		s.reply(req.ID, res, err)
		return
	}
	if s.opts.StartupProblem != "" {
		s.reply(req.ID, nil, engineError(500, s.opts.StartupProblem))
		return
	}
	key := string(req.ID)
	rctx, cancel := context.WithCancel(ctx)
	s.mu.Lock()
	if _, busy := s.inflight[key]; busy {
		s.mu.Unlock()
		cancel()
		s.reply(req.ID, nil, newError(CodeInvalidRequest, "The request id is already in use."))
		return
	}
	s.inflight[key] = cancel
	s.mu.Unlock()
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		released := false
		// release frees the id once, so a deferred call after the early one cannot drop a request that reused the id.
		release := func() {
			if released {
				return
			}
			released = true
			s.mu.Lock()
			delete(s.inflight, key)
			s.mu.Unlock()
			cancel()
		}
		defer release()
		res, err := s.invoke(rctx, method, h, call)
		// The id is free before the reply leaves: a client that reuses it right after the answer must not be refused.
		release()
		s.reply(req.ID, res, err)
	}()
}

// validID reports whether raw is a JSON string or an integer.
func validID(raw json.RawMessage) bool {
	if raw[0] == '"' {
		return true
	}
	digits := bytes.TrimPrefix(raw, []byte("-"))
	if len(digits) == 0 {
		return false
	}
	for _, c := range digits {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// cancel handles `$/cancelRequest`: an unknown or finished id, or malformed params, is ignored.
func (s *Server) cancel(params json.RawMessage) {
	var p struct {
		ID json.RawMessage `json:"id"`
	}
	if json.Unmarshal(params, &p) != nil || len(p.ID) == 0 {
		return
	}
	s.mu.Lock()
	cancel := s.inflight[string(p.ID)]
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

// invoke runs a handler and turns a panic into -32603. The panic value can hold anything, so only
// its type and the stack go to the log.
func (s *Server) invoke(ctx context.Context, method string, h Handler, call Call) (res any, err error) {
	defer func() {
		if r := recover(); r != nil {
			s.logf("panic in %s: %T\n%s", method, r, debug.Stack())
			res, err = nil, newError(CodeInternal, "Internal error.")
		}
	}()
	return h(ctx, call)
}

type response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *Error          `json:"error,omitempty"`
}

// reply sends the response for id (nil means null). On err the result is ignored.
func (s *Server) reply(id json.RawMessage, result any, err error) {
	if id == nil {
		id = json.RawMessage("null")
	}
	resp := response{JSONRPC: "2.0", ID: id}
	if err != nil {
		resp.Error = toError(err)
	} else if raw, eerr := Encode(result); eerr != nil {
		s.logf("a result could not be encoded")
		resp.Error = newError(CodeInternal, "Internal error.")
	} else {
		resp.Result = bytes.TrimSuffix(raw, []byte("\n"))
	}
	line, eerr := Encode(resp)
	if eerr == nil && len(line)-1 > MaxResponseLine {
		resp.Result = nil
		resp.Error = engineError(413, "The result is too large.")
		line, eerr = Encode(resp)
	}
	if eerr != nil {
		s.logf("a response could not be encoded")
		return
	}
	s.send(line)
}

// notify sends a notification; one that cannot be encoded or is too large is dropped.
func (s *Server) notify(method string, params any) {
	line, err := Encode(struct {
		JSONRPC string `json:"jsonrpc"`
		Method  string `json:"method"`
		Params  any    `json:"params"`
	}{"2.0", method, params})
	if err != nil || len(line)-1 > MaxResponseLine {
		s.logf("a notification was dropped")
		return
	}
	s.send(line)
}

func (s *Server) send(line []byte) {
	select {
	case s.out <- line:
	case <-s.stop:
	}
}

// writeLoop is the only writer. After a write error it keeps draining so senders never block.
func (s *Server) writeLoop(w io.Writer) {
	defer close(s.writerDone)
	var failed bool
	write := func(b []byte) {
		if failed {
			return
		}
		if _, err := w.Write(b); err != nil {
			failed = true
			s.logf("output closed")
		}
	}
	for {
		select {
		case b := <-s.out:
			write(b)
		case <-s.stop:
			for {
				select {
				case b := <-s.out:
					write(b)
				default:
					return
				}
			}
		}
	}
}

func (s *Server) logf(format string, args ...any) {
	fmt.Fprintf(s.opts.Log, "spacevibe: "+format+"\n", args...)
}
