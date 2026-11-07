//go:build !unix

package mutate

import "os"

// openNonblocking is a plain open: Windows has no FIFO in the file namespace to block on.
func openNonblocking(path string) (*os.File, error) { return os.Open(path) }
