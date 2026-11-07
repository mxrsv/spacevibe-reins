//go:build !unix

package fsx

import "io/fs"

// Windows has no uid or group/world bits in this sense: the check is skipped.
func ownedAndPrivate(fs.FileInfo) bool { return true }
