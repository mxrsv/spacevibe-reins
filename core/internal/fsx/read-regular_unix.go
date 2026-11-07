//go:build unix

package fsx

import (
	"os"
	"syscall"
)

// openNonblocking returns at once for a FIFO with no writer; OpenRegular then refuses it.
func openNonblocking(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_RDONLY|syscall.O_NONBLOCK, 0)
}
