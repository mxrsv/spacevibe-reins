package roots

import (
	"syscall"
	"unsafe"
)

// canonicalCase returns path spelled as the volume stores it. macOS volumes are case-insensitive by
// default, and realpath(3) (which the Swift code used) returns the stored spelling, while
// filepath.EvalSymlinks keeps the caller's. Without this, /users/ME/.claude would slip past a guard
// that compares against /Users/me (H4). F_GETPATH asks the kernel for the path of an open file; on
// any failure the input is returned unchanged.
func canonicalCase(path string) string {
	// O_EVTONLY opens without read access and without blocking, so a FIFO or an unreadable folder is fine.
	fd, err := syscall.Open(path, syscall.O_EVTONLY, 0)
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
