package rpc

import (
	"bytes"
	"encoding/json"
)

// Encode is the wire encoder: compact JSON, no HTML escaping, one trailing newline. The RPC
// responses and the one-shot `--json` commands both use it, so a contract test can compare bytes.
// Never use it for golden text: that goes through goldentest.Canonical.
func Encode(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
