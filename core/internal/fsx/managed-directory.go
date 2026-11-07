package fsx

import (
	"os"
	"path/filepath"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/roots"
)

// ManagedDirectory returns <data>/<name> after checking that SpaceVibe may manage it: it must be a real
// directory (not a link, not a file) owned by the current user and not writable by group or
// others (unix; G-fix.20), and its real path must stay inside the real data folder,
// including under SPACEVIBE_TEST=1 (where a path under the real home is refused first).
// Moved here from StatuslineSetup.managedDirectory so limits never imports mutate.
func ManagedDirectory(cfg config.Config, r roots.Roots, name string) (string, error) {
	folder := filepath.Join(r.Data, name)
	if err := roots.RefuseRealHomeUnderTest(cfg, folder); err != nil {
		return "", err
	}
	if info, err := os.Lstat(folder); err == nil {
		if !info.IsDir() {
			return "", coreerr.NewStatus("The collector directory is not a regular directory.", coreerr.StatusConflict)
		}
		if !ownedAndPrivate(info) {
			return "", coreerr.NewStatus("The collector directory is not owned by you or can be written by others.", coreerr.StatusConflict)
		}
	}
	if roots.ResolvedPath(folder) != filepath.Join(roots.ResolvedPath(r.Data), name) {
		return "", coreerr.NewStatus("The collector directory leaves the SpaceVibe data folder.", coreerr.StatusConflict)
	}
	return folder, nil
}
