// Package fsx holds the filesystem primitives every Reins write goes through: the atomic write,
// the symlink-aware target lookup, the write lock (in-process and cross-process) and the managed
// directory check.
// Ported from Sources/ReinsCore/FileEditAtomicWrite.swift, WriteLock.swift, TailReader.swift
// (modificationTime), StatuslineSetup.swift (managedDirectory) and the filesystem parts of
// FileEdit.swift (resolveTarget, the byte re-check before the rename). The orchestration of an edit
// (backup, journal op) belongs to the mutate package.
package fsx

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io/fs"
	"os"
	"strconv"

	"spacevibe.dev/core/internal/coreerr"
)

// AtomicWriteOptions are the two optional checks around the rename.
type AtomicWriteOptions struct {
	// Validate gets the bytes read back from the temp file. Returning an error aborts before the
	// rename, the temp file is removed and the target is untouched. The error is returned as is.
	Validate func(written []byte) error
	// BeforeRename runs right before the rename, after Validate. An error aborts and removes the
	// temp file. An edit uses it to refuse (409) when the target changed since it was read.
	BeforeRename func() error
}

// AtomicWrite writes data next to path and renames it over path, so a reader never sees half a file.
//
// path must be a real path (symlinks already resolved, see ResolveTarget), so the target is written
// and a link to it stays a link. The temp file is "<path>.spacevibe-<pid>-<8 hex>.tmp", unique per
// call, created with O_EXCL (never writes through a link or into a file somebody else made at that
// name), set to exactly mode's permission bits (the umask may have trimmed them) and fsynced.
// Errors are coreerr.Error with status 500 and never quote file content. On any failure after the
// temp file was created it is removed. A file at the temp name that this call did not create is
// never removed.
func AtomicWrite(path string, data []byte, mode os.FileMode, opts AtomicWriteOptions) error {
	temp, err := tempName(path)
	if err != nil {
		return coreerr.NewStatus("Could not write next to "+path+". Nothing was changed.", coreerr.StatusInternalFailure)
	}
	created, err := createTemp(temp, data, mode.Perm())
	if err != nil {
		if created {
			_ = os.Remove(temp)
		}
		return err
	}
	if err := finish(temp, path, opts); err != nil {
		_ = os.Remove(temp)
		return err
	}
	return nil
}

func finish(temp, path string, opts AtomicWriteOptions) error {
	if opts.Validate != nil {
		written, err := os.ReadFile(temp)
		if err != nil {
			return coreerr.NewStatus("Could not read back "+temp+" to check it.", coreerr.StatusInternalFailure)
		}
		if err := opts.Validate(written); err != nil {
			return err
		}
	}
	if opts.BeforeRename != nil {
		if err := opts.BeforeRename(); err != nil {
			return err
		}
	}
	if err := os.Rename(temp, path); err != nil {
		return coreerr.NewStatus("Could not replace "+path+" ("+reason(err)+"). Nothing was changed.", coreerr.StatusInternalFailure)
	}
	return nil
}

// createTemp reports whether the temp file now exists because of this call.
func createTemp(temp string, data []byte, mode os.FileMode) (created bool, err error) {
	f, err := os.OpenFile(temp, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return false, coreerr.NewStatus("Could not write next to "+temp+" ("+reason(err)+"). Nothing was changed.", coreerr.StatusInternalFailure)
	}
	_, werr := f.Write(data)
	if werr == nil {
		werr = f.Chmod(mode)
	}
	if werr == nil {
		werr = f.Sync()
	}
	if cerr := f.Close(); werr == nil {
		werr = cerr
	}
	if werr != nil {
		return true, coreerr.NewStatus("Could not write "+temp+" ("+reason(werr)+"). Nothing was changed.", coreerr.StatusInternalFailure)
	}
	return true, nil
}

func tempName(path string) (string, error) {
	var b [4]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return path + ".spacevibe-" + strconv.Itoa(os.Getpid()) + "-" + hex.EncodeToString(b[:]) + ".tmp", nil
}

// reason is the operating system's text for err, without the path.
func reason(err error) string {
	var pe *fs.PathError
	var le *os.LinkError
	switch {
	case errors.As(err, &pe):
		return pe.Err.Error()
	case errors.As(err, &le):
		return le.Err.Error()
	}
	return err.Error()
}
