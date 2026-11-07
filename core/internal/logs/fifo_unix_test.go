//go:build unix

package logs

import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"testing"
	"time"
)

// withFIFORescue runs body and fails the test instead of hanging when a reader blocks on a FIFO with no writer.
// Start with no writer; if body has not returned after 250 ms, open the FIFO for writing (retrying on ENXIO until the
// reader has opened) so each blocked open returns (a reader may open more than once), then fail. Needing the rescue is itself a failure.
// Swift: ReadHardeningTests.swift withFIFORescue.
func withFIFORescue(t *testing.T, fifo string, body func()) {
	t.Helper()
	done := make(chan struct{})
	rescued := make(chan struct{})
	rescuerDone := make(chan struct{})
	var once sync.Once
	go func() {
		defer close(rescuerDone)
		select {
		case <-done:
			return
		case <-time.After(250 * time.Millisecond):
		}
		for {
			fd, err := syscall.Open(fifo, syscall.O_WRONLY|syscall.O_NONBLOCK, 0)
			if err == nil {
				once.Do(func() { close(rescued) })
				syscall.Close(fd)
			}
			select {
			case <-done:
				return
			case <-time.After(10 * time.Millisecond):
			}
		}
	}()
	body()
	close(done)
	<-rescuerDone
	select {
	case <-rescued:
		t.Error("a log reader must reject a FIFO without a writer, not wait for one")
	default:
	}
}

func makeFIFO(t *testing.T) (fifo, link string) {
	t.Helper()
	dir := t.TempDir()
	fifo = filepath.Join(dir, "input.jsonl")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Fatal(err)
	}
	link = filepath.Join(dir, "input-link.jsonl")
	if err := os.Symlink(fifo, link); err != nil {
		t.Fatal(err)
	}
	return fifo, link
}

// FIFO refusal. Swift: ReadHardeningTests.swift "inventory readers reject FIFOs and links to FIFOs without waiting for
// input" covers InventoryFileIO (G2.1); the log readers share the same trap, so the same cases run here.
func TestFIFOIsRefusedWithoutWaiting(t *testing.T) {
	fifo, link := makeFIFO(t)
	for _, path := range []string{fifo, link} {
		t.Run(filepath.Base(path), func(t *testing.T) {
			withFIFORescue(t, fifo, func() {
				if _, err := NewTailReader(path, TailOptions{}).Read(func([]byte) {}, nil); !errors.Is(err, ErrNotRegular) {
					t.Errorf("TailReader: err = %v, want ErrNotRegular", err)
				}
				if err := ForEachChunk(path, func([]byte) error { return nil }); !errors.Is(err, ErrNotRegular) {
					t.Errorf("ForEachChunk: err = %v, want ErrNotRegular", err)
				}
				if _, err := ForEachLine(path, 0, func([]byte) error { return nil }); !errors.Is(err, ErrNotRegular) {
					t.Errorf("ForEachLine: err = %v, want ErrNotRegular", err)
				}
			})
		})
	}
}

func TestFIFOWithZstdNameIsRefused(t *testing.T) {
	dir := t.TempDir()
	fifo := filepath.Join(dir, "input.jsonl.zst")
	if err := syscall.Mkfifo(fifo, 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "input-link.jsonl.zst")
	if err := os.Symlink(fifo, link); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{fifo, link} {
		withFIFORescue(t, fifo, func() {
			if _, err := OpenZstdStream(path, 0); !errors.Is(err, ErrCannotOpen) {
				t.Errorf("OpenZstdStream: err = %v, want ErrCannotOpen", err)
			}
			if _, err := NewCompressedLogReader(path, CompressedOptions{}).Read(func([]byte) {}, nil); !errors.Is(err, ErrCannotOpen) {
				t.Errorf("CompressedLogReader: err = %v, want ErrCannotOpen", err)
			}
		})
	}
}

// Walk lists regular files only: a FIFO named like a log is not a log.
func TestWalkSkipsFIFO(t *testing.T) {
	dir := t.TempDir()
	if err := syscall.Mkfifo(filepath.Join(dir, "pipe.jsonl"), 0o600); err != nil {
		t.Fatal(err)
	}
	writeFile(t, dir, "real.jsonl", []byte("{}\n"))
	got := relativeTo(dir, Walk(dir))
	if len(got) != 1 || got[0] != "real.jsonl" {
		t.Errorf("walk = %v, want [real.jsonl]", got)
	}
}
