package roots

import (
	"path/filepath"
	"slices"
	"strings"
)

// ResolvedPath is the real path with every symlink followed. For a path that does not exist yet, the
// deepest existing ancestor is resolved and the rest appended, so a symlinked parent cannot hide a
// missing leaf. filepath.EvalSymlinks alone fails on a missing path, hence the walk.
// Ported from Roots.resolvedPath (Roots.swift:104-117).
func ResolvedPath(path string) string {
	current := standardized(path)
	var tail []string
	for {
		if resolved, err := filepath.EvalSymlinks(current); err == nil {
			slices.Reverse(tail)
			return filepath.Join(append([]string{canonicalCase(resolved)}, tail...)...)
		}
		parent := filepath.Dir(current)
		if parent == current {
			return standardized(path)
		}
		tail = append(tail, filepath.Base(current))
		current = parent
	}
}

// standardized is the absolute, cleaned path; symlinks are not followed.
func standardized(path string) string {
	if abs, err := filepath.Abs(path); err == nil {
		return abs
	}
	return filepath.Clean(path)
}

// isUnder reports whether path is directory or inside it. A sibling that only shares a name prefix
// is not under it.
func isUnder(path, directory string) bool {
	return path == directory || strings.HasPrefix(path, strings.TrimSuffix(directory, string(filepath.Separator))+string(filepath.Separator))
}
