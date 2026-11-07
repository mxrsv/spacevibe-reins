package fsx

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"syscall"

	"spacevibe.dev/core/internal/coreerr"
)

// The small write primitives besides AtomicWrite. Each one asks the write guard first (see
// write-guard.go) and returns coreerr.Error values that name a path and never file content.

// CreateFileExclusive creates path with exactly mode's permission bits (the umask may not trim
// them), writes data, fsyncs the file and its folder. It fails with 409 if anything exists at path,
// including a link (O_EXCL never follows one). The folder must exist. A partly written file is
// removed again. Callers use NewFileMode (0600) unless the file is meant to be shared.
func CreateFileExclusive(path string, data []byte, mode os.FileMode) error {
	if err := checkWrite(path); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode.Perm())
	if err != nil {
		if errors.Is(err, fs.ErrExist) {
			return coreerr.NewStatus(path+" already exists, so it was left alone.", coreerr.StatusConflict)
		}
		return coreerr.NewStatus("Could not create "+path+" ("+reason(err)+"). Nothing was changed.", coreerr.StatusInternalFailure)
	}
	_, werr := f.Write(data)
	if werr == nil {
		werr = f.Chmod(mode.Perm())
	}
	if werr == nil {
		werr = f.Sync()
	}
	if cerr := f.Close(); werr == nil {
		werr = cerr
	}
	if werr != nil {
		_ = os.Remove(path) // this call created it (O_EXCL)
		return coreerr.NewStatus("Could not write "+path+" ("+reason(werr)+"). Nothing was changed.", coreerr.StatusInternalFailure)
	}
	syncDir(filepath.Dir(path))
	return nil
}

// RemoveFile deletes one file or one link (a link is removed, never what it points at). A folder is
// refused with 409, a missing path with 404. It never removes recursively.
func RemoveFile(path string) error {
	if err := checkWrite(path); err != nil {
		return err
	}
	info, err := os.Lstat(path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return coreerr.NewStatus(path+" does not exist.", coreerr.StatusNotFound)
		}
		return coreerr.NewStatus("Could not remove "+path+" ("+reason(err)+").", coreerr.StatusInternalFailure)
	}
	if info.IsDir() {
		return coreerr.NewStatus(path+" is a folder, so it was left alone.", coreerr.StatusConflict)
	}
	if err := os.Remove(path); err != nil {
		return coreerr.NewStatus("Could not remove "+path+" ("+reason(err)+").", coreerr.StatusInternalFailure)
	}
	syncDir(filepath.Dir(path))
	return nil
}

// RemoveTree deletes path and everything under it (links inside are removed, not followed). It
// refuses a relative path, a filesystem root and a missing path is not an error. Meant for SpaceVibe's
// own scratch such as an abandoned backup folder, never for user content (that goes to the trash).
func RemoveTree(path string) error {
	if err := checkWrite(path); err != nil {
		return err
	}
	if !filepath.IsAbs(path) || filepath.Dir(path) == path {
		return coreerr.NewStatus("Refusing to remove "+path+".", coreerr.StatusForbidden)
	}
	if err := os.RemoveAll(path); err != nil {
		return coreerr.NewStatus("Could not remove "+path+" ("+reason(err)+").", coreerr.StatusInternalFailure)
	}
	syncDir(filepath.Dir(path))
	return nil
}

// Symlink creates a link at linkPath that holds the text target. It fails with 409 if anything
// exists at linkPath. target is stored as given (it may be relative or dangling); only linkPath is
// checked by the guard because creating a link changes nothing at target.
func Symlink(target, linkPath string) error {
	if err := checkWrite(linkPath); err != nil {
		return err
	}
	if err := os.Symlink(target, linkPath); err != nil {
		if errors.Is(err, fs.ErrExist) {
			return coreerr.NewStatus(linkPath+" already exists, so it was left alone.", coreerr.StatusConflict)
		}
		return coreerr.NewStatus("Could not create the link "+linkPath+" ("+reason(err)+"). Nothing was changed.", coreerr.StatusInternalFailure)
	}
	syncDir(filepath.Dir(linkPath))
	return nil
}

// MkdirExclusive creates the single folder path with perm (the umask applies) and fails with 409
// if anything exists there, a link included. The parent must exist. A caller that must own what it
// creates (so a rollback never removes somebody else's folder) uses it where MkdirAll cannot say
// whether it created the folder.
func MkdirExclusive(path string, perm os.FileMode) error {
	if err := checkWrite(path); err != nil {
		return err
	}
	if err := os.Mkdir(path, perm); err != nil {
		if errors.Is(err, fs.ErrExist) {
			return coreerr.NewStatus(path+" already exists, so it was left alone.", coreerr.StatusConflict)
		}
		return coreerr.NewStatus("Could not create the folder "+path+" ("+reason(err)+"). Nothing was changed.", coreerr.StatusInternalFailure)
	}
	syncDir(filepath.Dir(path))
	return nil
}

// MkdirAll creates path and any missing parents with perm (the umask applies). An existing folder
// is fine.
func MkdirAll(path string, perm os.FileMode) error {
	if err := checkWrite(path); err != nil {
		return err
	}
	if err := os.MkdirAll(path, perm); err != nil {
		return coreerr.NewStatus("Could not create the folder "+path+" ("+reason(err)+"). Nothing was changed.", coreerr.StatusInternalFailure)
	}
	return nil
}

// Move renames from to to and fails with 409 instead of replacing when to exists. Both paths are
// guarded. When the two are on different volumes (EXDEV, what Go's rename returns where
// FileManager.moveItem silently copied, H13) it copies the whole tree (files, folders, links as
// links, permission bits and times kept), fsyncs the copy and its folder, then removes the source;
// a failed copy removes the partial copy and leaves the source alone. The folder of to is fsynced
// after the rename.
func Move(from, to string) error { return moveWith(from, to, os.Rename) }

// MoveWith is Move with the rename step supplied by the caller. A caller's test uses it to make the
// rename fail with EXDEV and so exercise the cross-volume copy (H13) through its own code path;
// production code passes os.Rename (or calls Move).
func MoveWith(from, to string, rename func(oldpath, newpath string) error) error {
	return moveWith(from, to, rename)
}

func moveWith(from, to string, rename func(oldpath, newpath string) error) error {
	if err := checkWrite(from, to); err != nil {
		return err
	}
	if _, err := os.Lstat(to); err == nil {
		return coreerr.NewStatus("Could not move "+from+" (the destination already exists).", coreerr.StatusConflict)
	} else if !errors.Is(err, fs.ErrNotExist) {
		return coreerr.NewStatus("Could not move "+from+" ("+reason(err)+").", coreerr.StatusInternalFailure)
	}
	err := rename(from, to)
	if errors.Is(err, syscall.EXDEV) {
		err = copyThenRemove(from, to)
	}
	if err != nil {
		if _, ok := coreerr.As(err); ok {
			return err
		}
		return coreerr.NewStatus("Could not move "+from+" ("+reason(err)+").", coreerr.StatusInternalFailure)
	}
	syncDir(filepath.Dir(to))
	syncDir(filepath.Dir(from))
	return nil
}

func copyThenRemove(from, to string) error {
	if err := copyTree(from, to); err != nil {
		_ = os.RemoveAll(to) // to did not exist before this call
		return err
	}
	syncDir(filepath.Dir(to))
	if err := os.RemoveAll(from); err != nil {
		// The copy is complete; keep it and report, so the user sees both rather than losing data.
		return coreerr.NewStatus("Copied "+from+" to "+to+" but could not remove the original ("+reason(err)+").", coreerr.StatusInternalFailure)
	}
	return nil
}

func copyTree(from, to string) error {
	info, err := os.Lstat(from)
	if err != nil {
		return err
	}
	switch {
	case info.Mode()&fs.ModeSymlink != 0:
		target, err := os.Readlink(from)
		if err != nil {
			return err
		}
		return os.Symlink(target, to)
	case info.IsDir():
		if err := os.Mkdir(to, info.Mode().Perm()|0o700); err != nil {
			return err
		}
		entries, err := os.ReadDir(from)
		if err != nil {
			return err
		}
		for _, e := range entries {
			if err := copyTree(filepath.Join(from, e.Name()), filepath.Join(to, e.Name())); err != nil {
				return err
			}
		}
		if err := os.Chmod(to, info.Mode().Perm()); err != nil {
			return err
		}
		return os.Chtimes(to, info.ModTime(), info.ModTime())
	case info.Mode().IsRegular():
		return copyRegular(from, to, info)
	}
	return coreerr.NewStatus(from+" is not a regular file, folder or link, so it was not moved.", coreerr.StatusConflict)
}

func copyRegular(from, to string, info fs.FileInfo) error {
	in, err := os.Open(from)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(to, os.O_WRONLY|os.O_CREATE|os.O_EXCL, info.Mode().Perm()|0o200)
	if err != nil {
		return err
	}
	_, err = io.Copy(out, in)
	if err == nil {
		err = out.Chmod(info.Mode().Perm())
	}
	if err == nil {
		err = out.Sync()
	}
	if cerr := out.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return err
	}
	return os.Chtimes(to, info.ModTime(), info.ModTime())
}

// syncDirFunc is the directory fsync, replaceable by a test.
var syncDirFunc = syncDirectory

// syncDir flushes a folder's entries (a rename, a create, a remove) to disk so they survive a
// crash right after the call (G-fix.20). It is best effort: the change has already happened, and
// some filesystems refuse to fsync a folder, so a failure is not reported as a failed write.
func syncDir(dir string) { _ = syncDirFunc(dir) }

func syncDirectory(dir string) error {
	if runtime.GOOS == "windows" {
		return nil // Windows cannot fsync a folder handle
	}
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	err = d.Sync()
	if cerr := d.Close(); err == nil {
		err = cerr
	}
	return err
}
