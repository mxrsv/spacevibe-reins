//go:build unix

package fsx

import (
	"errors"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestReadRegularRefusesFIFOWithoutWaiting(t *testing.T) {
	fifo := filepath.Join(t.TempDir(), "fifo")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { _, err := ReadRegular(fifo, 10); done <- err }()
	select {
	case err := <-done:
		if !errors.Is(err, ErrNotRegular) {
			t.Fatalf("err = %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("ReadRegular blocked on a FIFO")
	}
}
