package clis

import (
	"io/fs"
	"path/filepath"
)

// StatFunc is os.Stat. Installed takes it so a test can record every path it looks at.
type StatFunc func(name string) (fs.FileInfo, error)

// Installed reports whether the CLI is installed (spec MC-R3, MC8): root, its resolved root folder, is a folder, or
// one of its Binaries is an executable file in a folder of searchPath (the PATH folders, in order). A relative PATH
// folder depends on the working directory and is skipped. It only calls stat: it never starts a process, not even
// `<cli> --version` (S-R4, D-4).
func Installed(d Descriptor, root string, searchPath []string, stat StatFunc) bool {
	if root != "" {
		if info, err := stat(root); err == nil && info.IsDir() {
			return true
		}
	}
	for _, name := range d.Binaries {
		for _, dir := range searchPath {
			if !filepath.IsAbs(dir) {
				continue
			}
			info, err := stat(filepath.Join(dir, name))
			if err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0 {
				return true
			}
		}
	}
	return false
}
