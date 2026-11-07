package fsx

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"syscall"
)

// ErrNotRegular is returned for a path that is a FIFO, device, socket or folder. Opening a FIFO with no writer
// blocks forever, so a bounded read refuses such a path before it can wait on it (G-fix.11).
var ErrNotRegular = errors.New("not a regular file")

// ErrTooLarge is returned by ReadRegular when the file is longer than the cap.
var ErrTooLarge = errors.New("file is larger than the allowed size")

// OpenRegular opens path read-only without blocking and returns it only if the opened descriptor is a regular
// file, so a path swapped for a FIFO between a stat and the open is refused too. Symlinks to regular files are
// followed. The error is the OS error, ErrNotRegular, or nil.
func OpenRegular(path string) (*os.File, error) {
	f, err := openNonblocking(path)
	if err != nil {
		return nil, err
	}
	info, err := f.Stat()
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

// ReadRegular is the whole file, read through OpenRegular, at most maxBytes long: a longer file gives
// ErrTooLarge and no data. Errors never carry file content.
func ReadRegular(path string, maxBytes int64) ([]byte, error) {
	f, err := OpenRegular(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > maxBytes {
		return nil, ErrTooLarge
	}
	return data, nil
}

// Presence is the answer to "is anything at this path?", from a stat that follows symlinks.
type Presence int

const (
	// Present: the stat succeeded.
	Present Presence = iota
	// Missing: ENOENT or ENOTDIR, so nothing is there.
	Missing
	// Unknown: the lookup failed for another reason (EACCES, EPERM, ELOOP, ...), so the path may well exist.
	// A denied parent folder must not read as "gone".
	Unknown
)

// PathPresence stats path (following symlinks). Only ENOENT and ENOTDIR mean Missing.
func PathPresence(path string) Presence {
	_, err := os.Stat(path)
	switch {
	case err == nil:
		return Present
	case errors.Is(err, syscall.ENOENT), errors.Is(err, syscall.ENOTDIR), errors.Is(err, fs.ErrNotExist):
		return Missing
	default:
		return Unknown
	}
}
