//go:build unix

package fsx

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"spacevibe.dev/core/internal/coreerr"
)

func TestMoveCrossDeviceFailureLeavesSourceAndNoPartialCopy(t *testing.T) {
	skipOnWindows(t)
	dir := tempDir(t)
	from, to := filepath.Join(dir, "from"), filepath.Join(dir, "to")
	writeFile(t, filepath.Join(from, "a"), "a", 0o600)
	fifo := filepath.Join(from, "pipe") // not copyable
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Skip(err)
	}
	exdev := func(string, string) error { return syscall.EXDEV }
	err := moveWith(from, to, exdev)
	wantStatus(t, err, coreerr.StatusConflict)
	if readFile(t, filepath.Join(from, "a")) != "a" {
		t.Error("source was damaged")
	}
	if _, err := os.Lstat(to); err == nil {
		t.Error("partial copy left behind")
	}
}
