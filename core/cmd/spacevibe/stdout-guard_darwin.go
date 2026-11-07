package main

import (
	"os"
	"syscall"
)

// guardStdout returns a private duplicate of fd 1 for the protocol and points fd 1 and os.Stdout at
// stderr, so a stray print or a child process lands in the log, not in the stream. The duplicate is
// not fd 1 or 2, so a closed pipe gives a write error, not SIGPIPE.
func guardStdout() (*os.File, error) {
	syscall.ForkLock.RLock()
	fd, err := syscall.Dup(syscall.Stdout)
	if err == nil {
		syscall.CloseOnExec(fd)
	}
	syscall.ForkLock.RUnlock()
	if err != nil {
		return nil, err
	}
	if err := syscall.Dup2(syscall.Stderr, syscall.Stdout); err != nil {
		syscall.Close(fd)
		return nil, err
	}
	os.Stdout = os.Stderr
	return os.NewFile(uintptr(fd), "protocol"), nil
}
