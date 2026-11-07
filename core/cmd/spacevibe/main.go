// Command spacevibe is the core engine. The app spawns it as `spacevibe rpc` (docs/internals/core-protocol.md).
package main

import (
	"fmt"
	"io"
	"os"

	"spacevibe.dev/core/internal/identity"
	"spacevibe.dev/core/internal/statusline"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintf(stderr, "usage: %s --version | rpc\n", identity.Name)
		return 2
	}
	if len(args) == 1 && args[0] == "--version" {
		fmt.Fprintf(stdout, "%s %s\n", identity.Name, identity.Version)
		return 0
	}
	if args[0] == "rpc" {
		return runRPC(args[1:], stderr)
	}
	if args[0] == "statusline" { // the collector Claude runs; os.Stdin/Stdout/Stderr go to the original command as they are
		return statusline.Run(args[1:], os.Stdin, os.Stdout, os.Stderr)
	}
	fmt.Fprintf(stderr, "%s: unknown command %q\n", identity.Name, args[0])
	return 2
}
