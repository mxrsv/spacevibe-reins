// Package statusline is the Claude Code status line collector and its setup (decision D-3: a core subcommand, not
// a separate binary). Ported from Sources/ReinsCore/StatuslineSetup.swift, Sources/ReinsStatusline/main.swift and
// the write side of Sources/ReinsCore/LimitsClaudeStatusline.swift; internal/limits has the read side.
//
//	spacevibe statusline install
//	spacevibe statusline uninstall
//	spacevibe statusline undo <journal-id>
//	spacevibe statusline capture <data> <claudeRoot> <original>
//
// install is explicit setup: it wraps the status line command in Claude's settings so Claude runs capture, which
// runs the original command unchanged and keeps a bounded snapshot of the rate limits. Claude starts capture; the app
// never launches a recorded command. uninstall is the way back that survives later edits of the settings: one journaled
// edit that restores the original command. capture, install and uninstall are not RPC methods (rpc_cannot_capture).
package statusline

import (
	"fmt"
	"io"

	"spacevibe.dev/core/internal/identity"
)

// Subcommand names, as typed after "spacevibe statusline".
const (
	cmdInstall   = "install"
	cmdUninstall = "uninstall"
	cmdUndo      = "undo"
	cmdCapture   = "capture"
)

// Run is `spacevibe statusline <args>`. stdin, stdout and stderr should be the process files: capture hands stdout
// and stderr to the original command as they are, so it prints exactly where it would without the wrapper.
// It returns the process exit status.
func Run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) > 0 {
		switch {
		case args[0] == cmdCapture:
			return runCapture(args[1:], stdin, stdout, stderr)
		case args[0] == cmdInstall && len(args) == 1:
			return runInstall(stdout, stderr)
		case args[0] == cmdUninstall && len(args) == 1:
			return runUninstall(stdout, stderr)
		case args[0] == cmdUndo && len(args) == 2:
			return runUndo(args[1], stdout, stderr)
		}
	}
	report(stderr, "Usage: "+identity.Name+" statusline install | uninstall | undo <journal-id> | capture <data> <claudeRoot> <original>")
	return 2
}

// report writes one fixed sentence to stderr. Never pass file content or an error payload to it.
func report(stderr io.Writer, message string) {
	fmt.Fprintf(stderr, "%s: %s\n", identity.Name, message)
}
