//go:build !(darwin || linux || freebsd || netbsd || openbsd || dragonfly)

package fsx

import "os"

// No cross-process lock on this platform yet: only the process-wide lock of WithWriteLock applies,
// and a second process is caught only by the byte re-check before the rename (UnchangedSince).
// Windows would use LockFileEx; the Windows track (X2) decides whether to add it.
func tryLockFile(*os.File) (bool, error) { return true, nil }

func unlockFile(*os.File) {}
