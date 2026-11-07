package main

import (
	"context"
	"fmt"
	"io"
	"os"

	"spacevibe.dev/core/internal/identity"
	"spacevibe.dev/core/internal/rpc"
	"spacevibe.dev/core/internal/rpc/methods"
)

// runRPC serves the protocol on stdin and the guarded stdout until stdin ends.
func runRPC(args []string, stderr io.Writer) int {
	if len(args) != 0 {
		fmt.Fprintf(stderr, "usage: %s rpc\n", identity.Name)
		return 2
	}
	protocol, err := guardStdout()
	if err != nil {
		fmt.Fprintf(stderr, "%s: cannot reserve stdout for the protocol\n", identity.Name)
		return 1
	}
	reg := rpc.NewRegistry()
	registerDebugMethods(reg) // no-op unless built with -tags contracttest
	opts := rpc.Options{Log: stderr}
	env, problem := loadEnvironment()
	if problem != nil {
		// initialize still answers; every other method answers with the sentence (the server holds it).
		opts.StartupProblem = problem.Error()
		methods.RegisterUnavailable(reg)
	} else {
		services := methods.New(env.cfg, env.roots, env.adapter, stderr)
		defer services.Close()
		services.Register(reg)
	}
	srv := rpc.NewServer(reg, opts)
	if err := srv.Serve(context.Background(), os.Stdin, protocol); err != nil {
		fmt.Fprintf(stderr, "%s: stdin could not be read\n", identity.Name)
		return 1
	}
	return 0
}
