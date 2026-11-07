//go:build darwin || linux || freebsd || netbsd || openbsd || dragonfly

package fsx

import (
	"errors"
	"os"
	"syscall"
)

// lockFile takes an exclusive advisory lock, waiting for it. flock locks belong to the open file
// description, so two descriptors in one process also exclude each other.
func lockFile(f *os.File) error {
	for {
		err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX)
		if !errors.Is(err, syscall.EINTR) {
			return err
		}
	}
}

// unlockFile releases the lock; closing the file would release it too, and so does the process dying.
func unlockFile(f *os.File) { _ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN) }
