package fsx

import (
	"io/fs"
	"time"
)

// ModificationTime is the file's modification time, to the nanosecond where the filesystem keeps it.
// Swift's modificationTime(_:) picked st_mtimespec on Darwin and st_mtim elsewhere; Go's
// os.FileInfo already does that, so this is only a named, documented entry point.
func ModificationTime(info fs.FileInfo) time.Time { return info.ModTime() }
