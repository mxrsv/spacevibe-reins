//go:build !darwin

package main

import "os"

// guardStdout keeps the original stdout for the protocol and points os.Stdout at stderr. Unlike the
// darwin version it cannot redirect fd 1 itself, so only Go-level prints are caught here.
func guardStdout() (*os.File, error) {
	protocol := os.Stdout
	os.Stdout = os.Stderr
	return protocol, nil
}
