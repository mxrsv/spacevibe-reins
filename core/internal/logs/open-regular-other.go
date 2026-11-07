//go:build !unix

package logs

import "os"

// openForRead is a plain open: Windows has no FIFO in the file namespace to block on.
func openForRead(path string) (*os.File, error) {
	return os.Open(path)
}
