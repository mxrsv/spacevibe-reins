package fsx

import (
	"sync/atomic"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/roots"
)

// The write guard (G-fix.2). Every primitive in this package that changes the disk (AtomicWrite,
// CreateFileExclusive, Move, MoveWith, RemoveFile, RemoveTree, Symlink, MkdirAll, MkdirExclusive,
// WithWriteLock) asks the
// guard about each path it is about to change, before it touches anything. No caller has to
// remember a check.
//
// Design: one process-wide hook, set once at startup. With no hook installed the primitives write
// freely (production). The process entry point calls InstallWriteGuard(cfg) right after
// config.Load; with SPACEVIBE_TEST=1 that installs roots.RefuseRealHomeUnderTest, so a test that
// misdirects a root can never write under the real home. Tests of other packages that must prove the
// guard is armed call InstallWriteGuard(config.Config{Test: true}) from TestMain. A hook (not a
// Config argument on every primitive) keeps every existing signature unchanged.

var writeGuard atomic.Pointer[func(path string) error]

// SetWriteGuard installs guard, called with each path a primitive is about to change; a non-nil
// error aborts that primitive before anything is touched. nil removes the guard. A guard error that
// is not a coreerr.Error is replaced by a fixed 500 sentence.
func SetWriteGuard(guard func(path string) error) {
	if guard == nil {
		writeGuard.Store(nil)
		return
	}
	writeGuard.Store(&guard)
}

// InstallWriteGuard arms the real-home guard when cfg.Test is set (SPACEVIBE_TEST=1) and removes any
// guard otherwise.
func InstallWriteGuard(cfg config.Config) {
	if !cfg.Test {
		SetWriteGuard(nil)
		return
	}
	SetWriteGuard(func(path string) error { return roots.RefuseRealHomeUnderTest(cfg, path) })
}

// checkWrite runs the guard over paths and returns the first refusal.
func checkWrite(paths ...string) error {
	guard := writeGuard.Load()
	if guard == nil {
		return nil
	}
	for _, p := range paths {
		if err := (*guard)(p); err != nil {
			if _, ok := coreerr.As(err); ok {
				return err
			}
			return coreerr.NewStatus("A write was refused by the write guard.", coreerr.StatusInternalFailure)
		}
	}
	return nil
}
