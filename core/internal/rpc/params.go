package rpc

import (
	"bytes"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
)

// DecodeParams decodes a params member into dst strictly: absent or null means `{}`, anything but
// an object is refused, and an unknown member is refused (a misspelled `verdict` must not fall back
// to a default). The -32602 message names the member, never its value.
func DecodeParams(raw json.RawMessage, dst any) error {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || bytes.Equal(raw, []byte("null")) {
		raw = []byte("{}")
	}
	if raw[0] != '{' {
		return newError(CodeInvalidParams, "Invalid params: params must be an object.")
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return paramsError(err)
	}
	return nil
}

const unknownFieldPrefix = "json: unknown field "

func paramsError(err error) *Error {
	var te *json.UnmarshalTypeError
	if errors.As(err, &te) {
		field := te.Field
		if field == "" {
			field = "params"
		}
		return newError(CodeInvalidParams, "Invalid params: "+field+" has the wrong type.")
	}
	if rest, ok := strings.CutPrefix(err.Error(), unknownFieldPrefix); ok {
		if name, qerr := strconv.Unquote(rest); qerr == nil {
			return newError(CodeInvalidParams, "Invalid params: "+strconv.Quote(name)+" is not a known member.")
		}
	}
	return newError(CodeInvalidParams, "Invalid params.")
}
