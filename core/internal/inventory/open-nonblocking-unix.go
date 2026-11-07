//go:build unix

package inventory

import (
	"os"
	"syscall"
)

// openNonblocking opens read-only without blocking, so a FIFO with no writer returns at once and is then
// refused by the descriptor check.
func openNonblocking(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_RDONLY|syscall.O_NONBLOCK, 0)
}
