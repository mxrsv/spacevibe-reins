package mutate

import "spacevibe.dev/core/internal/coreerr"

// Fixed sentences that more than one file uses. None of them quotes file content (S-R3).
const (
	// UnreadableMessage is shown when a write path meets a journal it cannot read. It never quotes the file.
	UnreadableMessage = "The undo history (journal.json) is not valid JSON, so it was not written. Fix or move the file, then try again."

	// RollbackFailureMessage is shown when a failed change could not be fully put back.
	RollbackFailureMessage = "The change failed and could not be fully rolled back. Some configuration may have changed. Review the configuration and the saved copies in the SpaceVibe trash before trying again."

	// PartlyUndoneMessage is shown when an undo failed part way and some of the ops it had already reversed could not be put back (G-fix.9).
	PartlyUndoneMessage = "The undo failed part way and some changes could not be put back, so this entry is partly undone. Review the files and the saved copies in the SpaceVibe trash."

	outsideManagedMessage = "This history entry points outside the folders SpaceVibe manages, so it was not undone. Nothing was changed."
	unknownEntryMessage   = "Unknown history entry."
)

// fail is a coreerr.Error with the given status.
func fail(message string, status int) error { return coreerr.NewStatus(message, status) }

// need returns a 400 (or the given status) error unless condition holds.
func need(condition bool, message string, status ...int) error {
	if condition {
		return nil
	}
	if len(status) > 0 {
		return fail(message, status[0])
	}
	return coreerr.New(message)
}

// chainedError is a safe, user-facing error that keeps the error that led to it (G-fix.9). Error shows only the safe
// message; Unwrap lists the safe error first, so coreerr.As finds it and errors.Is/As still reach the cause.
type chainedError struct {
	safe  coreerr.Error
	cause error
}

func (e *chainedError) Error() string   { return e.safe.Message }
func (e *chainedError) Unwrap() []error { return []error{e.safe, e.cause} }

// chain returns safe with cause behind it.
func chain(safe coreerr.Error, cause error) error { return &chainedError{safe: safe, cause: cause} }

// statusOf is the coreerr status in err's chain, or 0.
func statusOf(err error) int {
	if e, ok := coreerr.As(err); ok {
		return e.Status
	}
	return 0
}
