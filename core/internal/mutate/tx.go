package mutate

import (
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/roots"
)

// Tx is the handle of a held write lock. It exists only inside WithLock, and its methods assume the lock
// is held and never take it, so a body cannot nest a locking call (fsx.WithWriteLock is not re-entrant).
type Tx struct {
	r roots.Roots
}

// WithLock runs fn under the one write lock (in-process mutex plus the flock on <data>/write.lock) with a
// handle for the locked steps. If the lock cannot be taken, fn does not run.
func WithLock(r roots.Roots, fn func(tx *Tx) error) error {
	return fsx.WithWriteLock(r.Data, func() error { return fn(&Tx{r: r}) })
}

// locked is WithLock for a body that returns a value.
func locked[T any](r roots.Roots, fn func(tx *Tx) (T, error)) (T, error) {
	return fsx.WithWriteLockValue(r.Data, func() (T, error) { return fn(&Tx{r: r}) })
}

// Roots are the roots the handle works on.
func (tx *Tx) Roots() roots.Roots { return tx.r }
