// Command spacevibe is the core engine. The app spawns it; `rpc` lands in PR.2.
package main

import (
	"fmt"
	"io"
	"os"

	"spacevibe.dev/core/internal/identity"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintf(stderr, "usage: %s --version\n", identity.Name)
		return 2
	}
	if len(args) == 1 && args[0] == "--version" {
		fmt.Fprintf(stdout, "%s %s\n", identity.Name, identity.Version)
		return 0
	}
	fmt.Fprintf(stderr, "%s: unknown command %q\n", identity.Name, args[0])
	return 2
}
