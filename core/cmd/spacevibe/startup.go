package main

import (
	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
)

// environment is what a command needs to run: the validated config, the roots derived from it and the
// process adapter.
type environment struct {
	cfg     config.Config
	roots   roots.Roots
	adapter proc.Adapter
}

// loadEnvironment reads and validates the environment. The error is the startup sentence of
// docs/internals/core-protocol.md ("Startup problem"): it comes from config, roots or proc and names a
// variable or a root, never file content.
//
// The write guard is armed right after the config loads and before anything else can write, so under
// SPACEVIBE_TEST=1 no primitive in fsx writes under the real home whatever the roots say (S-R1).
func loadEnvironment() (environment, error) {
	cfg, err := config.Load()
	if err != nil {
		return environment{}, err
	}
	fsx.InstallWriteGuard(cfg)
	home, err := roots.RealHome()
	if err != nil {
		return environment{}, err
	}
	r, err := roots.Resolve(cfg, home)
	if err != nil {
		return environment{}, err
	}
	adapter, err := proc.New(cfg, cfg.ProcFixture)
	if err != nil {
		return environment{}, err
	}
	return environment{cfg: cfg, roots: r, adapter: adapter}, nil
}
