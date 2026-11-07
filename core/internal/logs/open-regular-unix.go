//go:build unix

package logs

import (
	"os"
	"syscall"
)

// openForRead opens without blocking, so a FIFO swapped in after the Stat check returns at once and is then refused.
func openForRead(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_RDONLY|syscall.O_NONBLOCK, 0)
}
