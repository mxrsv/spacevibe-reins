package fsx

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"time"

	"spacevibe.dev/core/internal/coreerr"
)

// LockFileName is the cross-process lock file inside the data folder.
const LockFileName = "write.lock"

// processLock serializes the writers of this process. It is a one-slot semaphore, not a mutex, so a waiter can give
// up when its context ends. It is not re-entrant.
var processLock = make(chan struct{}, 1)

// How long a writer waits for the lock before it gives up, and the pause between two tries of the cross-process
// lock (doubling from first to max). The wait is a poll on LOCK_NB, because a blocking flock cannot be cancelled.
const (
	lockWaitLimit = 30 * time.Second
	lockPollFirst = 20 * time.Millisecond
	lockPollMax   = 200 * time.Millisecond
)

// errLockTimeout is the cause of the wait deadline, to tell it from a cancel of the caller's context.
var errLockTimeout = errors.New("write lock wait limit reached")

// WithWriteLock runs fn while holding the one write lock around every write SpaceVibe makes to config,
// the journal and the trash: a process-wide lock, then an exclusive flock on <dataDir>/write.lock,
// so a second SpaceVibe process (the Swift app, another core) is excluded too. fn's error is returned
// as is. If the lock cannot be taken within 30 s, fn does not run (fail closed) and the error is the fixed
// "Could not lock" 500. WithWriteLockContext is the same for a caller that can be cancelled.
// Ported from WriteLock.run (WriteLock.swift); the cross-process part is new (X-lock).
//
// The Swift lock was an NSRecursiveLock, nested by addHook -> FileEdit -> Journal. This one is NOT
// re-entrant: a nested call from inside fn waits until the wait limit and then fails, on the process lock
// and, even from another goroutine, on the flock. Convention, "locked entry, unlocked body":
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
	return WithWriteLockContext(context.Background(), dataDir, fn)
}

// WithWriteLockValue is WithWriteLock for a body that returns a value (for example a journal entry).
func WithWriteLockValue[T any](dataDir string, fn func() (T, error)) (T, error) {
	return WithWriteLockValueContext(context.Background(), dataDir, fn)
}

// WithWriteLockContext is WithWriteLock for a request that can be cancelled: while it waits for the lock (in this
// process or for another one) a cancelled ctx ends the wait with ctx's error, context.Canceled, and fn does not run.
// A ctx whose deadline passes, like the 30 s wait limit, gives the fixed "Could not lock" 500. Once fn runs, ctx is
// fn's business: the lock is held until fn returns.
func WithWriteLockContext(ctx context.Context, dataDir string, fn func() error) error {
	_, err := WithWriteLockValueContext(ctx, dataDir, func() (struct{}, error) { return struct{}{}, fn() })
	return err
}

// WithWriteLockValueContext is WithWriteLockContext for a body that returns a value.
func WithWriteLockValueContext[T any](ctx context.Context, dataDir string, fn func() (T, error)) (T, error) {
	return withWriteLock(ctx, dataDir, lockWaitLimit, fn)
}

// withWriteLock is the lock with the wait limit as a parameter (tests shorten it).
func withWriteLock[T any](ctx context.Context, dataDir string, limit time.Duration, fn func() (T, error)) (T, error) {
	var zero T
	if err := checkWrite(dataDir); err != nil {
		return zero, err
	}
	if err := ctx.Err(); err != nil {
		return zero, waitFailure(ctx)
	}
	wait, cancel := context.WithTimeoutCause(ctx, limit, errLockTimeout)
	defer cancel()
	select {
	case processLock <- struct{}{}:
	case <-wait.Done():
		return zero, waitFailure(ctx)
	}
	defer func() { <-processLock }()
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return zero, lockError()
	}
	f, err := os.OpenFile(filepath.Join(dataDir, LockFileName), os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		return zero, lockError()
	}
	defer f.Close()
	if err := lockFileWait(wait, f); err != nil {
		if errors.Is(err, errWaitEnded) {
			return zero, waitFailure(ctx)
		}
		return zero, lockError()
	}
	defer unlockFile(f)
	return fn()
}

// errWaitEnded says the wait context ended (cancel or limit) while the flock was still held by someone else.
var errWaitEnded = errors.New("wait ended")

// lockFileWait takes the flock by trying without blocking and pausing 20 ms, doubling to 200 ms, between tries, so
// it can stop as soon as ctx ends. The first try is immediate: an uncontended lock costs one syscall.
func lockFileWait(ctx context.Context, f *os.File) error {
	delay := lockPollFirst
	for {
		locked, err := tryLockFile(f)
		if err != nil {
			return err
		}
		if locked {
			return nil
		}
		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return errWaitEnded
		case <-timer.C:
		}
		delay = min(delay*2, lockPollMax)
	}
}

// waitFailure is the error of a wait that ended: the caller's cancel as it is (the protocol answers it as a cancelled
// request), anything else (the wait limit, the caller's own deadline) the fixed lock sentence.
func waitFailure(parent context.Context) error {
	if err := parent.Err(); errors.Is(err, context.Canceled) {
		return err
	}
	return lockError()
}

func lockError() error {
	return coreerr.NewStatus("Could not lock the SpaceVibe data folder, so nothing was changed.", coreerr.StatusInternalFailure)
}
