package roots

import (
	"os"
	"path/filepath"
	"strings"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
)

type labelled struct{ label, path string }

func assertNotUnderRealHome(realHome string, list []labelled) error {
	for _, r := range list {
		if isUnderRealHome(realHome, r.path) {
			return &UnderRealHomeError{Label: r.label, Path: r.path}
		}
	}
	return nil
}

// dataVolumePrefix is the macOS firmlink of the data volume: /System/Volumes/Data/Users/me is the
// same folder as /Users/me, yet it is neither a symlink (EvalSymlinks keeps it) nor the same
// spelling. The inode check below catches it for an existing ancestor; stripping the prefix catches
// it by name too (G-fix.2).
const dataVolumePrefix = "/System/Volumes/Data"

func stripDataVolume(path string) string {
	if strings.HasPrefix(path, dataVolumePrefix+"/") {
		return strings.TrimPrefix(path, dataVolumePrefix)
	}
	return path
}

// isUnderRealHome reports whether path is realHome or inside it, three ways: by spelling (lexical and
// with links resolved, with and without the data-volume prefix), by case (ResolvedPath asks the
// volume for its stored spelling), and by identity: every existing ancestor of path is stat-ed
// (links followed) and compared by device and inode with the real home, so a Unicode normalization
// or case spelling the string checks cannot see, a firmlink, or a symlink into the home still
// matches. A path with missing components is judged by its deepest existing ancestors.
func isUnderRealHome(realHome, path string) bool {
	homes := []string{standardized(realHome), ResolvedPath(realHome)}
	candidates := []string{standardized(path), ResolvedPath(path)}
	for _, c := range candidates {
		for _, h := range homes {
			if isUnder(c, h) || isUnder(stripDataVolume(c), stripDataVolume(h)) {
				return true
			}
		}
	}
	home, err := os.Stat(realHome)
	if err != nil {
		return false
	}
	for _, start := range append([]string{path}, candidates...) {
		if hasAncestorSameFile(start, home) {
			return true
		}
	}
	return false
}

// hasAncestorSameFile walks start and every ancestor up to the root, and reports whether one of
// them is the same file as target (same device and inode on unix, same file index on windows).
func hasAncestorSameFile(start string, target os.FileInfo) bool {
	for current := start; ; {
		if info, err := os.Stat(current); err == nil && os.SameFile(target, info) {
			return true
		}
		parent := filepath.Dir(current)
		if parent == current {
			return false
		}
		current = parent
	}
}

// RefuseRealHomeUnderTest is defense in depth for tests: with cfg.Test set, a path under the real
// home is never written, whatever the roots say. It returns a coreerr.Error with status 500. If the
// real home cannot be determined it refuses too (fail closed).
// Ported from FileEdit.refuseRealHomeUnderTest (FileEdit.swift:186-192); G-fix.2 added the
// data-volume and inode checks.
func RefuseRealHomeUnderTest(cfg config.Config, path string) error {
	if !cfg.Test {
		return nil
	}
	real, err := RealHome()
	if err != nil {
		return coreerr.NewStatus(envTest+"=1: cannot tell where the real home is, so the write was refused.", coreerr.StatusInternalFailure)
	}
	if isUnderRealHome(real, path) {
		return coreerr.NewStatus(envTest+"=1: refusing to write under the real home.", coreerr.StatusInternalFailure)
	}
	return nil
}
