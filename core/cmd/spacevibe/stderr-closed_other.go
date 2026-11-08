//go:build !unix

package main

// keepAliveOnClosedStderr does nothing here: Windows has no SIGPIPE, a write to a closed pipe is an error.
func keepAliveOnClosedStderr() {}
