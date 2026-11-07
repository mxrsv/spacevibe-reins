package main

import (
	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/roots"
)

// startupProblem is the sentence every method but `initialize` answers with when the environment
// is refused (docs/internals/core-protocol.md, "Startup problem"); empty when it is fine. The
// messages come from config and roots: they name a variable or a root, never file content.
func startupProblem() string {
	cfg, err := config.Load()
	if err != nil {
		return err.Error()
	}
	home, err := roots.RealHome()
	if err != nil {
		return err.Error()
	}
	if _, err := roots.Resolve(cfg, home); err != nil {
		return err.Error()
	}
	return ""
}
