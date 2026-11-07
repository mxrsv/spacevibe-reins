package main

import (
	"context"
	"fmt"
	"io"
	"os"

	"spacevibe.dev/core/internal/identity"
	"spacevibe.dev/core/internal/rpc"
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
	registerDebugMethods(reg) // no-op unless built with -tags contracttest; domain methods are wired by later tasks
	srv := rpc.NewServer(reg, rpc.Options{StartupProblem: startupProblem(), Log: stderr})
	if err := srv.Serve(context.Background(), os.Stdin, protocol); err != nil {
		fmt.Fprintf(stderr, "%s: stdin could not be read\n", identity.Name)
		return 1
	}
	return 0
}
