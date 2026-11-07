package methods

import (
	"context"
	"fmt"
	"io"
	"sync"
	"time"

	"spacevibe.dev/core/internal/activity"
	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/rpc"
	"spacevibe.dev/core/internal/rules"
	"spacevibe.dev/core/internal/usage"
)

// Services are the domain services of one process, built once. The inventory and rules services share one
// project list: every inventory read hands its list to rules, and a refresh in rules goes through inventory.
type Services struct {
	cfg       config.Config
	roots     roots.Roots
	inventory *inventory.Service
	usage     *usage.Scanner
	activity  *activity.Service
	mutate    *mutate.Service
	rules     *rules.Service
	// now is the clock; tests may replace it before Register.
	now func() time.Time
	log io.Writer

	handlers map[string]rpc.Handler

	watchMu  sync.Mutex
	watching *watch
	closed   bool
}

// New builds the services over cfg and the process adapter. log receives one fixed line per unexpected
// handler failure; nil discards.
func New(cfg config.Config, r roots.Roots, adapter proc.Adapter, log io.Writer) *Services {
	if log == nil {
		log = io.Discard
	}
	scanner := usage.NewScanner(r)
	inv := inventory.NewService(r, scanner)
	rs := rules.NewService(r)
	rs.Discover = inv.RefreshProjects
	s := &Services{
		cfg: cfg, roots: r, inventory: inv, usage: scanner,
		activity: activity.NewService(r, adapter, activity.DefaultOptions(), nil),
		mutate:   mutate.NewService(r), rules: rs, now: time.Now, log: log,
	}
	s.handlers = s.buildHandlers()
	return s
}

// Register adds every domain method to reg.
func (s *Services) Register(reg *rpc.Registry) {
	for name, h := range s.handlers {
		reg.Register(name, h)
	}
}

// Run calls a registered handler without a server: the one-shot commands use it. It has no request id and
// no notifications.
func (s *Services) Run(ctx context.Context, method string, params []byte) (any, error) {
	h, ok := s.handlers[method]
	if !ok {
		return nil, fmt.Errorf("methods: %q is not registered", method)
	}
	return h(ctx, rpc.Call{Params: params})
}

// Close stops every activity watcher. The entry point calls it when the session ends; no watcher starts after.
func (s *Services) Close() {
	s.watchMu.Lock()
	s.closed = true
	w := s.watching
	s.watching = nil
	s.watchMu.Unlock()
	w.stop()
}

// RegisterUnavailable adds every domain method with a handler that answers 500. The server never reaches it
// while it holds a startup problem; it keeps the method list the same whether or not the environment is fine.
func RegisterUnavailable(reg *rpc.Registry) {
	for _, name := range rpc.AllMethods {
		if name == rpc.MethodInitialize {
			continue
		}
		reg.Register(name, func(context.Context, rpc.Call) (any, error) {
			return nil, errUnavailable
		})
	}
}
