package rpc

import (
	"context"
	"errors"

	"spacevibe.dev/core/internal/coreerr"
)

// JSON-RPC error codes (docs/internals/core-protocol.md, "Errors").
const (
	CodeParse           = -32700
	CodeInvalidRequest  = -32600
	CodeMethodNotFound  = -32601
	CodeInvalidParams   = -32602
	CodeInternal        = -32603
	CodeEngine          = -32000
	CodeProtocolVersion = -32001
	CodeNotInitialized  = -32002
	CodeCancelled       = -32800
)

// Error is a JSON-RPC error object. Message must be a fixed sentence: it is sent to the shell, so
// it never quotes request or file content (S-R3).
type Error struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func (e *Error) Error() string { return e.Message }

// engineData is the `data` of a -32000 error.
type engineData struct {
	Status  int    `json:"status"`
	Message string `json:"message"`
}

func newError(code int, message string) *Error { return &Error{Code: code, Message: message} }

// engineError is -32000 with data {status, message}; message repeats the top-level one.
func engineError(status int, message string) *Error {
	return &Error{Code: CodeEngine, Message: message, Data: engineData{Status: status, Message: message}}
}

// toError maps what a handler returned to the error the shell sees. Only an *Error and a
// coreerr.Error carry a message that is safe to forward; anything else becomes the fixed -32603.
func toError(err error) *Error {
	var re *Error
	if errors.As(err, &re) {
		return re
	}
	if ce, ok := coreerr.As(err); ok {
		return engineError(ce.Status, ce.Message)
	}
	if errors.Is(err, context.Canceled) {
		return newError(CodeCancelled, "Request cancelled.")
	}
	return newError(CodeInternal, "Internal error.")
}
