package mutate

import (
	"context"

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

// WithLockContext is WithLock for a request that can be cancelled: while it waits for the lock, a cancelled ctx ends
// the wait with context.Canceled and fn does not run (fsx.WithWriteLockContext).
func WithLockContext(ctx context.Context, r roots.Roots, fn func(tx *Tx) error) error {
	return fsx.WithWriteLockContext(ctx, r.Data, func() error { return fn(&Tx{r: r}) })
}

// locked is WithLock for a body that returns a value.
func locked[T any](r roots.Roots, fn func(tx *Tx) (T, error)) (T, error) {
	return fsx.WithWriteLockValue(r.Data, func() (T, error) { return fn(&Tx{r: r}) })
}

// Roots are the roots the handle works on.
func (tx *Tx) Roots() roots.Roots { return tx.r }

// lockedContext is locked for a request that can be cancelled. The wait for the lock ends as soon as ctx does, and ctx
// is looked at again as the first step inside the lock, so a request that was cancelled while it waited for the lock
// never changes anything.
func lockedContext[T any](ctx context.Context, r roots.Roots, fn func(tx *Tx) (T, error)) (T, error) {
	return fsx.WithWriteLockValueContext(ctx, r.Data, func() (T, error) {
		tx := &Tx{r: r}
		if err := ctx.Err(); err != nil {
			var zero T
			return zero, err
		}
		return fn(tx)
	})
}
