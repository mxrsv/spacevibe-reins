//go:build unix

package statusline

import (
	"os"
	"os/signal"
	"syscall"
)

// ignoreBrokenPipe keeps a write to a closed stdout or stderr from killing the collector, as signal(SIGPIPE,
// SIG_IGN) did in Swift. It uses Notify and not Ignore on purpose: an ignored signal is inherited by the original
// command, but a handled one is reset to the default by exec, so the original still dies of SIGPIPE like it would
// started by Claude directly (hypothesis H6, scripts/test-statusline.sh).
func ignoreBrokenPipe() { signal.Notify(make(chan os.Signal, 1), syscall.SIGPIPE) }

// exitStatus is the shell's own: the exit code, or 128 plus the signal that ended it.
func exitStatus(state *os.ProcessState) int {
	if status, ok := state.Sys().(syscall.WaitStatus); ok {
		if status.Signaled() {
			return 128 + int(status.Signal())
		}
		return status.ExitStatus()
	}
	return state.ExitCode()
}
