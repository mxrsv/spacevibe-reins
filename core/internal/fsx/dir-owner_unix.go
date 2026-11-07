//go:build unix

package fsx

import (
	"io/fs"
	"os"
	"syscall"
)

// ownedAndPrivate reports whether the folder belongs to the current user and no one else can write
// into it (no group or world write bit).
func ownedAndPrivate(info fs.FileInfo) bool {
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return false // cannot tell: fail closed
	}
	return int(st.Uid) == os.Getuid() && info.Mode().Perm()&0o022 == 0
}
