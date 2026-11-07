package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
)

// Handler runs one request. Its result is encoded with Encode. It returns an *Error, a
// coreerr.Error or context.Canceled to answer with a specific error; any other error becomes the
// fixed -32603. A handler must stop when ctx is cancelled, except while it holds the write lock
// and has started a write: a started write finishes and returns its real result.
type Handler func(ctx context.Context, call Call) (any, error)

// Call is what a handler gets besides its context.
type Call struct {
	// ID is the request id as sent. It is what a progress notification names.
	ID json.RawMessage
	// Params is the raw params member: empty, null or a JSON value. Decode it with DecodeParams.
	Params json.RawMessage
	// Session is cancelled when the connection's input ends (and when Serve returns), before the drain wait. A
	// handler that starts work that outlives its request, such as the Activity poll, derives its context from it so
	// end of input stops that work. It is nil outside a server.
	Session context.Context

	notify func(method string, params any)
}

// Notify sends a notification to the shell, such as `usage/progress`. It never blocks past the end
// of the session.
func (c Call) Notify(method string, params any) {
	if c.notify != nil {
		c.notify(method, params)
	}
}

// Registry maps method names to handlers. Register everything before Serve starts: the registry is
// not locked.
type Registry struct {
	handlers map[string]Handler
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry { return &Registry{handlers: map[string]Handler{}} }

// Register adds a method. A duplicate or empty name is a programming error and panics.
func (r *Registry) Register(name string, h Handler) {
	if name == "" || h == nil {
		panic("rpc: Register needs a name and a handler")
	}
	if _, dup := r.handlers[name]; dup {
		panic(fmt.Sprintf("rpc: method %q registered twice", name))
	}
	r.handlers[name] = h
}

// Methods lists the registered names, sorted. This is the `methods` of the handshake result.
func (r *Registry) Methods() []string {
	names := make([]string, 0, len(r.handlers))
	for n := range r.handlers {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

func (r *Registry) lookup(name string) (Handler, bool) {
	h, ok := r.handlers[name]
	return h, ok
}
