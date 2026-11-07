package mutate

import (
	"errors"
	"io"
	"os"
)

var (
	errNotRegular = errors.New("not a regular file")
	errTooLarge   = errors.New("file too large")
)

// openRegular opens a file without blocking and checks the opened descriptor, not a path that could change
// between a stat and the open. A link to a regular file is followed (shared installs); a FIFO, a device or
// a folder is refused (G-fix.5, G-fix.11).
func openRegular(path string) (*os.File, error) {
	f, err := openNonblocking(path)
	if err != nil {
		return nil, err
	}
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		_ = f.Close()
		return nil, errNotRegular
	}
	return f, nil
}

// readRegular reads a whole regular file. limit < 0 means no limit; otherwise a larger file gives errTooLarge. The
// result is never nil on success (an empty file is an empty, non-nil slice).
func readRegular(path string, limit int64) ([]byte, error) {
	f, err := openRegular(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var r io.Reader = f
	if limit >= 0 {
		r = io.LimitReader(f, limit+1)
	}
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	if limit >= 0 && int64(len(data)) > limit {
		return nil, errTooLarge
	}
	if data == nil {
		data = []byte{}
	}
	return data, nil
}
