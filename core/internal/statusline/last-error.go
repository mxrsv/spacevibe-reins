package statusline

import (
	"os"
	"path/filepath"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/limits"
	"spacevibe.dev/core/internal/roots"
)

// Reasons are the fixed codes recorded in <data>/claude-limits/last-error when a capture fails (G-fix.19). The
// Swift collector printed to a stderr nobody reads, so a broken capture was invisible. A reason names a class of
// failure, never input, a path or an error payload (S-R3), so the file stays a few bytes.
const (
	ReasonInputTooLarge     = "input-too-large"
	ReasonInputUnreadable   = "input-unreadable"
	ReasonInvalidInput      = "invalid-input"
	ReasonInvalidLimits     = "invalid-limits"
	ReasonAccountUnknown    = "account-unknown"
	ReasonClaudeRootChanged = "claude-root-changed"
	ReasonFolderRefused     = "folder-refused"
	ReasonRootsRefused      = "roots-refused"
	ReasonWriteFailed       = "write-failed"
)

// LastErrorPath is where the last failure is recorded, under the data root: <data>/claude-limits/last-error.
func LastErrorPath(r roots.Roots) string {
	return filepath.Join(r.Data, limits.SnapshotDir, limits.LastErrorFile)
}

// recordFailure replaces the last-error file with reason and a newline. It is best effort and only writes through
// the managed folder, so a link out of the data root is never followed; a refusal leaves nothing behind.
func recordFailure(cfg config.Config, r roots.Roots, reason string) {
	folder, err := fsx.ManagedDirectory(cfg, r, limits.SnapshotDir)
	if err != nil || fsx.MkdirAll(folder, 0o700) != nil {
		return
	}
	_ = fsx.AtomicWrite(filepath.Join(folder, limits.LastErrorFile), []byte(reason+"\n"), 0o600, fsx.AtomicWriteOptions{})
}

// clearFailure removes the last-error file after a capture that worked. It does nothing when the file is absent,
// so a healthy status line costs one lstat.
func clearFailure(cfg config.Config, r roots.Roots) {
	folder, err := fsx.ManagedDirectory(cfg, r, limits.SnapshotDir)
	if err != nil {
		return
	}
	file := filepath.Join(folder, limits.LastErrorFile)
	if info, err := os.Lstat(file); err == nil && !info.IsDir() {
		_ = fsx.RemoveFile(file)
	}
}
