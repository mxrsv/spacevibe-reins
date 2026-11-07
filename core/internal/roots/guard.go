package roots

import (
	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
)

type labelled struct{ label, path string }

func assertNotUnderRealHome(realHome string, list []labelled) error {
	homes := []string{standardized(realHome), ResolvedPath(realHome)}
	for _, r := range list {
		for _, candidate := range []string{standardized(r.path), ResolvedPath(r.path)} {
			for _, home := range homes {
				if isUnder(candidate, home) {
					return &UnderRealHomeError{Label: r.label, Path: r.path}
				}
			}
		}
	}
	return nil
}

// RefuseRealHomeUnderTest is defense in depth for tests: with cfg.Test set, a path under the real
// home is never written, whatever the roots say. It returns a coreerr.Error with status 500. If the
// real home cannot be determined it refuses too (fail closed).
// Ported from FileEdit.refuseRealHomeUnderTest (FileEdit.swift:186-192).
func RefuseRealHomeUnderTest(cfg config.Config, path string) error {
	if !cfg.Test {
		return nil
	}
	real, err := RealHome()
	if err != nil {
		return coreerr.NewStatus(envTest+"=1: cannot tell where the real home is, so the write was refused.", coreerr.StatusInternalFailure)
	}
	if isUnder(ResolvedPath(path), ResolvedPath(real)) {
		return coreerr.NewStatus(envTest+"=1: refusing to write under the real home.", coreerr.StatusInternalFailure)
	}
	return nil
}
