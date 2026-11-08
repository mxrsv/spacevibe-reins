//go:build darwin || linux || freebsd || netbsd || openbsd || dragonfly

package fsx

import (
	"errors"
	"os"
	"syscall"
)

// tryLockFile asks for an exclusive advisory lock without waiting: false when another holder has it. flock locks
// belong to the open file description, so two descriptors in one process also exclude each other.
func tryLockFile(f *os.File) (bool, error) {
	for {
		err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		switch {
		case err == nil:
			return true, nil
		case errors.Is(err, syscall.EINTR):
		case errors.Is(err, syscall.EWOULDBLOCK):
			return false, nil
		default:
			return false, err
		}
	}
}

// unlockFile releases the lock; closing the file would release it too, and so does the process dying.
func unlockFile(f *os.File) { _ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN) }
