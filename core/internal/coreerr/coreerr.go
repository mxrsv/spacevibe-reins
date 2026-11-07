// Package coreerr is an error whose message is safe to show to the user.
// Ported from Sources/ReinsCore/ReinsError.swift (Node mutate UserError, git b58269d).
//
// The message may name a path or a rule, never file content (S-R3): a parse error from a settings
// file can quote a secret, so callers replace those with a fixed sentence.
package coreerr

import "errors"

// Status follows HTTP.
const (
	StatusBadRequest      = 400 // bad input (the default)
	StatusForbidden       = 403 // refused
	StatusNotFound        = 404 // gone
	StatusConflict        = 409 // conflicts with the current state: the file changed, or is not valid JSON
	StatusTooLarge        = 413 // too large
	StatusInternalFailure = 500 // the write failed
)

// Error is a safe message plus a status. It is comparable, like the Swift Equatable struct.
type Error struct {
	Message string
	Status  int
}

// New returns an error with StatusBadRequest.
func New(message string) Error { return Error{Message: message, Status: StatusBadRequest} }

// NewStatus returns an error with the given status.
func NewStatus(message string, status int) Error { return Error{Message: message, Status: status} }

// Error returns the safe message.
func (e Error) Error() string { return e.Message }

// As finds an Error anywhere in err's chain.
func As(err error) (Error, bool) {
	var e Error
	ok := errors.As(err, &e)
	return e, ok
}
