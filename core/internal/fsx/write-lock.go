package fsx

import (
	"os"
	"path/filepath"
	"sync"

	"spacevibe.dev/core/internal/coreerr"
)

// LockFileName is the cross-process lock file inside the data folder.
const LockFileName = "write.lock"

// processLock serializes the writers of this process. It is not re-entrant.
var processLock sync.Mutex

// WithWriteLock runs fn while holding the one write lock around every write Reins makes to config,
// the journal and the trash: a process-wide mutex, then an exclusive flock on <dataDir>/write.lock,
// so a second Reins process (the Swift app, another core) is excluded too. fn's error is returned
// as is. If the lock cannot be taken, fn does not run (fail closed).
// Ported from WriteLock.run (WriteLock.swift); the cross-process part is new (X-lock).
//
// The Swift lock was an NSRecursiveLock, nested by addHook -> FileEdit -> Journal. This one is NOT
// re-entrant: a nested call from inside fn blocks forever, on the mutex and, even from another
// goroutine, on the flock. Convention, "locked entry, unlocked body":
//
//	func Edit(...) error {                       // exported: takes the lock once
//		return fsx.WithWriteLock(dataDir, func() error { return editLocked(...) })
//	}
//	func editLocked(...) error { ... }           // unexported: assumes the lock is held, never takes it
//
// A body may call other *Locked functions and any function that does not take the lock; it must
// never call an exported locked entry. dataDir comes from roots.Resolve, which already refuses a
// folder under the real home under SPACEVIBE_TEST=1; the lock file is created with mode 0600 and
// the folder with 0700 when missing.
func WithWriteLock(dataDir string, fn func() error) error {
	_, err := WithWriteLockValue(dataDir, func() (struct{}, error) { return struct{}{}, fn() })
	return err
}

// WithWriteLockValue is WithWriteLock for a body that returns a value (for example a journal entry).
func WithWriteLockValue[T any](dataDir string, fn func() (T, error)) (T, error) {
	if err := checkWrite(dataDir); err != nil {
		var zero T
		return zero, err
	}
	processLock.Lock()
	defer processLock.Unlock()
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		var zero T
		return zero, lockError()
	}
	f, err := os.OpenFile(filepath.Join(dataDir, LockFileName), os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		var zero T
		return zero, lockError()
	}
	defer f.Close()
	if err := lockFile(f); err != nil {
		var zero T
		return zero, lockError()
	}
	defer unlockFile(f)
	return fn()
}

func lockError() error {
	return coreerr.NewStatus("Could not lock the Reins data folder, so nothing was changed.", coreerr.StatusInternalFailure)
}
