//go:build !unix

package statusline

import "os"

// ignoreBrokenPipe does nothing: there is no SIGPIPE here (and no /bin/sh, so capture only reports a failure).
func ignoreBrokenPipe() {}

func exitStatus(state *os.ProcessState) int {
	if code := state.ExitCode(); code >= 0 {
		return code
	}
	return 1
}
