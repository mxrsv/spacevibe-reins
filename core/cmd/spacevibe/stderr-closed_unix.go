//go:build unix

package main

import (
	"os"
	"os/signal"
	"syscall"
)

// keepAliveOnClosedStderr makes a write to a closed or reader-less stderr fail with EPIPE instead of ending the
// process. Go's runtime ends a program with SIGPIPE when a write to fd 1 or 2 hits a broken pipe, unless the program
// has asked for the signal; after guardStdout fd 1 is the same pipe as fd 2, and a log line must never kill the core.
// The channel is never read: a signal that finds it full is dropped, which is all this needs. (Notify, not Ignore:
// an ignored signal would also be inherited by the ps and lsof the core starts.)
func keepAliveOnClosedStderr() {
	signal.Notify(make(chan os.Signal, 1), syscall.SIGPIPE)
}
