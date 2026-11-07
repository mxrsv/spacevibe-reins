//go:build contracttest

package main

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"time"

	"spacevibe.dev/core/internal/rpc"
)

// fd1 is kept alive on purpose: a collected os.File would close fd 1.
var fd1 = os.NewFile(1, "fd1")

// registerDebugMethods adds the methods the contract tests need. They exist only in a binary built
// with -tags contracttest, never in the shipped one.
func registerDebugMethods(reg *rpc.Registry) {
	// debug.print writes to every stdout path a careless call could use.
	reg.Register("debug.print", func(context.Context, rpc.Call) (any, error) {
		fmt.Println("stray-println")
		os.Stdout.WriteString("stray-os-stdout\n")
		if runtime.GOOS == "darwin" { // only darwin redirects fd 1 itself
			fd1.WriteString("stray-fd1\n")
		}
		return map[string]bool{"printed": true}, nil
	})
	// debug.slow waits ms milliseconds. It stops on cancel unless uncancellable is set.
	reg.Register("debug.slow", func(ctx context.Context, call rpc.Call) (any, error) {
		var p struct {
			MS            int  `json:"ms"`
			Uncancellable bool `json:"uncancellable"`
		}
		if err := rpc.DecodeParams(call.Params, &p); err != nil {
			return nil, err
		}
		wait := ctx.Done()
		if p.Uncancellable {
			wait = nil
		}
		select {
		case <-time.After(time.Duration(p.MS) * time.Millisecond):
			return map[string]bool{"slept": true}, nil
		case <-wait:
			return nil, ctx.Err()
		}
	})
	// debug.panic panics with a value the response and the log must not repeat.
	reg.Register("debug.panic", func(context.Context, rpc.Call) (any, error) {
		panic("SECRET-PANIC-VALUE")
	})
}
