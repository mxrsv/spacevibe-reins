package roots

import (
	"os"
	"path/filepath"
	"syscall"
	"unsafe"
)

// canonicalCase returns path spelled as the volume stores it. macOS volumes are case-insensitive by
// default, and realpath(3) (which the Swift code used) returns the stored spelling, while
// filepath.EvalSymlinks keeps the caller's. Without this, /users/ME/.claude would slip past a guard
// that compares against /Users/me (H4). F_GETPATH asks the kernel for the path of an open file; on
// any failure the input is returned unchanged.
//
// Only a directory or a regular file is opened. open(2) on a FIFO blocks until a peer opens it, even
// with O_EVTONLY, which would hang a root that points at one. Any other kind (FIFO, socket, device,
// symlink) keeps its own name and takes the stored spelling of its parent. O_NONBLOCK still guards
// the window between the Lstat and the open, and O_CLOEXEC keeps the descriptor out of children.
func canonicalCase(path string) string {
	info, err := os.Lstat(path)
	if err != nil {
		return path
	}
	if !info.IsDir() && !info.Mode().IsRegular() {
		parent := filepath.Dir(path)
		if parent == path {
			return path
		}
		return filepath.Join(canonicalCase(parent), filepath.Base(path))
	}
	fd, err := syscall.Open(path, syscall.O_EVTONLY|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return path
	}
	defer syscall.Close(fd)
	var buf [1024]byte // MAXPATHLEN
	if _, _, errno := syscall.Syscall(syscall.SYS_FCNTL, uintptr(fd), uintptr(syscall.F_GETPATH), uintptr(unsafe.Pointer(&buf[0]))); errno != 0 {
		return path
	}
	n := 0
	for n < len(buf) && buf[n] != 0 {
		n++
	}
	if n == 0 {
		return path
	}
	return string(buf[:n])
}
