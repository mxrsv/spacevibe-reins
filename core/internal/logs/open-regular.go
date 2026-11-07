package logs

import (
	"errors"
	"os"
)

// ErrNotRegular is returned for a log path that is a FIFO, device, socket or directory. Opening a FIFO with no
// writer blocks forever, so every read in this package refuses such a path before it can wait on it.
var ErrNotRegular = errors.New("log is not a regular file")

// openRegular opens path for reading and returns it only if it is a regular file (symlinks are followed, as open
// does). A pre-check with Stat refuses a FIFO without opening it, so a blocked writer is never woken by us;
// the platform open (see open-regular-unix.go) then re-checks the descriptor against a swap in between.
func openRegular(path string) (*os.File, error) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, ErrNotRegular
	}
	f, err := openForRead(path)
	if err != nil {
		return nil, err
	}
	info, err = f.Stat()
	if err != nil {
		_ = f.Close()
		return nil, err
	}
	if !info.Mode().IsRegular() {
		_ = f.Close()
		return nil, ErrNotRegular
	}
	return f, nil
}
