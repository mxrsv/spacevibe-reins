package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"

	"spacevibe.dev/core/internal/identity"
	"spacevibe.dev/core/internal/rpc"
	"spacevibe.dev/core/internal/rpc/methods"
)

// oneShotMethods maps each one-shot command to the read method whose result it prints.
var oneShotMethods = map[string]string{
	"inventory": "inventory.read",
	"usage":     "usage.scan",
	"activity":  "activity.read",
	"limits":    "limits.read",
	"rules":     "rules.snapshot",
}

// isOneShot reports whether name is one of the --json commands.
func isOneShot(name string) bool { _, ok := oneShotMethods[name]; return ok }

// runOneShot is `spacevibe inventory|usage|activity|limits|rules --json [--dir <path>]`: it prints the result
// object of the matching read method with the encoder the RPC uses, so a contract test compares bytes. Exit
// codes: 0 success, 1 core error (the safe message on stderr), 2 usage. The only file it can write is the
// usage cache, as usage.scan does.
func runOneShot(name string, args []string, stdout, stderr io.Writer) int {
	usage := func() int {
		synopsis := name + " --json"
		if name == "rules" {
			synopsis += " [--dir <path>]"
		}
		fmt.Fprintf(stderr, "usage: %s %s\n", identity.Name, synopsis)
		return 2
	}
	var jsonFlag bool
	var dir *string
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--json":
			jsonFlag = true
		case args[i] == "--dir" && name == "rules" && i+1 < len(args) && dir == nil:
			i++
			dir = &args[i]
		default:
			return usage()
		}
	}
	if !jsonFlag {
		return usage()
	}
	params := json.RawMessage(`{}`)
	if name == "rules" {
		scope := map[string]any{"scope": "global", "dir": nil}
		if dir != nil {
			scope = map[string]any{"scope": "project", "dir": *dir}
		}
		params, _ = json.Marshal(scope)
	}
	env, err := loadEnvironment()
	if err != nil {
		fmt.Fprintf(stderr, "%s: %s\n", identity.Name, err.Error())
		return 1
	}
	services := methods.New(env.cfg, env.roots, env.adapter, stderr)
	defer services.Close()
	result, err := services.Run(context.Background(), oneShotMethods[name], params)
	if err != nil {
		fmt.Fprintf(stderr, "%s: %s\n", identity.Name, rpc.SafeMessage(err))
		return 1
	}
	line, err := rpc.Encode(result)
	if err != nil {
		fmt.Fprintf(stderr, "%s: the result could not be encoded\n", identity.Name)
		return 1
	}
	if _, err := stdout.Write(line); err != nil {
		fmt.Fprintf(stderr, "%s: the result could not be written\n", identity.Name)
		return 1
	}
	return 0
}
