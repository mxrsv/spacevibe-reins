package rpc

import (
	"bytes"
	"context"
	"encoding/json"

	"spacevibe.dev/core/internal/identity"
)

type nameVersion struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type initializeParams struct {
	ProtocolVersion json.RawMessage `json:"protocolVersion"`
	Client          *nameVersion    `json:"client"`
}

type initializeResult struct {
	ProtocolVersion int         `json:"protocolVersion"`
	Core            nameVersion `json:"core"`
	Identity        struct {
		EnvPrefix string `json:"envPrefix"`
		DataDir   string `json:"dataDir"`
	} `json:"identity"`
	Methods []string `json:"methods"`
}

// initialize is the handshake. The version is checked on the bare member first, so a client of a
// future version gets -32001 even when it also sends members this version does not know.
func (s *Server) initialize(_ context.Context, call Call) (any, error) {
	var loose struct {
		ProtocolVersion json.RawMessage `json:"protocolVersion"`
	}
	raw := bytes.TrimSpace(call.Params)
	if len(raw) == 0 || raw[0] != '{' {
		return nil, newError(CodeInvalidParams, "Invalid params: params must be an object.")
	}
	_ = json.Unmarshal(raw, &loose)
	if !bytes.Equal(bytes.TrimSpace(loose.ProtocolVersion), []byte("1")) {
		return nil, &Error{
			Code:    CodeProtocolVersion,
			Message: "Protocol version not supported.",
			Data:    map[string]int{"protocolVersion": ProtocolVersion},
		}
	}
	var p initializeParams
	if err := DecodeParams(raw, &p); err != nil {
		return nil, err
	}
	s.initialized = true
	res := initializeResult{
		ProtocolVersion: ProtocolVersion,
		Core:            nameVersion{Name: identity.Name, Version: identity.Version},
		Methods:         s.reg.Methods(),
	}
	res.Identity.EnvPrefix = identity.EnvPrefix
	res.Identity.DataDir = identity.DataDir
	return res, nil
}
