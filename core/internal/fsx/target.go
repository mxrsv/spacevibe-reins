package fsx

import (
	"bytes"
	"errors"
	"io/fs"
	"os"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/roots"
)

// NewFileMode is the mode of a file that does not exist yet.
const NewFileMode os.FileMode = 0o600

// Target is the file an edit writes.
type Target struct {
	// Real is the path to write, with every link followed (the path itself when it does not exist).
	Real string
	// Existed is false for a file that does not exist yet.
	Existed bool
	// Mode is the current permission bits, NewFileMode for a new file.
	Mode os.FileMode
}

// ResolveTarget follows links so the file a link points at is the one written, and a link stays a
// link. A link to nothing is refused with 409 (the Node core would replace the link with a regular
// file, which loses the user's link). A path that exists but is not a regular file is refused with
// 409. A path that cannot be stat-ed for any other reason counts as missing.
// Ported from FileEdit.resolveTarget (FileEdit.swift:171-183).
func ResolveTarget(path string) (Target, error) {
	_, lerr := os.Lstat(path)
	info, err := os.Stat(path)
	if err != nil {
		if lerr == nil {
			return Target{}, coreerr.NewStatus(path+" is a link to a file that does not exist, so it was left alone.", coreerr.StatusConflict)
		}
		return Target{Real: path, Existed: false, Mode: NewFileMode}, nil
	}
	if !info.Mode().IsRegular() {
		return Target{}, coreerr.NewStatus(path+" is not a regular file.", coreerr.StatusConflict)
	}
	return Target{Real: roots.ResolvedPath(path), Existed: true, Mode: info.Mode().Perm()}, nil
}

// UnchangedSince is the byte re-check an edit makes in BeforeRename: it reports whether path still
// holds exactly before. A nil before means the file did not exist and must still not exist; an
// empty non-nil slice is an existing empty file. A file that cannot be read for a reason other
// than being absent counts as changed (fail closed; Swift read it as absent).
// Ported from the beforeRename closure in FileEdit.applyLocked (FileEdit.swift:80-85).
func UnchangedSince(path string, before []byte) bool {
	now, err := os.ReadFile(path)
	if err != nil {
		return before == nil && errors.Is(err, fs.ErrNotExist)
	}
	return before != nil && bytes.Equal(now, before)
}
