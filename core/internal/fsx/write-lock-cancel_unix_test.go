//go:build unix

package fsx

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

// holdFlock takes the cross-process lock the way another SpaceVibe process would: on its own open file description.
// It returns the release func (also run at cleanup).
func holdFlock(t *testing.T, dataDir string) (release func()) {
	t.Helper()
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(filepath.Join(dataDir, LockFileName), os.O_RDWR|os.O_CREATE, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatal(err)
	}
	var once bool
	release = func() {
		if !once {
			once = true
			f.Close()
		}
	}
	t.Cleanup(release)
	return release
}

const lockSentence = "Could not lock the SpaceVibe data folder, so nothing was changed."

// A write queued behind another process's flock ends within the cancel, changes nothing, and the lock still works
// once the other process lets go.
func TestWriteLockContextCancelWhileAnotherProcessHoldsTheFlock(t *testing.T) {
	data := tempDir(t)
	target := filepath.Join(data, "shared.txt")
	writeFile(t, target, "keep\n", 0o600)
	release := holdFlock(t, data)

	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(100*time.Millisecond, cancel)
	ran := false
	started := time.Now()
	err := WithWriteLockContext(ctx, data, func() error {
		ran = true
		return appendLine(target, "from the cancelled write")
	})
	if elapsed := time.Since(started); elapsed > 500*time.Millisecond {
		t.Errorf("returned after %v, want within 500 ms of the cancel", elapsed)
	}
	if !errors.Is(err, context.Canceled) {
		t.Errorf("err = %v, want context.Canceled", err)
	}
	if ran {
		t.Error("the body ran without the lock")
	}
	if got := readFile(t, target); got != "keep\n" {
		t.Errorf("file changed: %q", got)
	}
	if len(strayTempFiles(t, data)) != 0 {
		t.Errorf("stray %v", strayTempFiles(t, data))
	}

	release()
	if err := WithWriteLockContext(context.Background(), data, func() error { return appendLine(target, "after") }); err != nil {
		t.Fatalf("a normal write after the release: %v", err)
	}
	if got := readFile(t, target); got != "keep\nafter\n" {
		t.Errorf("file = %q", got)
	}
}

// The process-wide part of the lock also gives way to a cancel: a writer parked behind another goroutine of this
// process (not behind a flock) leaves when its ctx ends.
func TestWriteLockContextCancelWhileThisProcessHoldsTheLock(t *testing.T) {
	data := tempDir(t)
	held, release := make(chan struct{}), make(chan struct{})
	holderDone := make(chan error, 1)
	go func() {
		holderDone <- WithWriteLock(data, func() error { close(held); <-release; return nil })
	}()
	<-held
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	started := time.Now()
	ran := false
	err := WithWriteLockContext(ctx, data, func() error { ran = true; return nil })
	if elapsed := time.Since(started); elapsed > 500*time.Millisecond {
		t.Errorf("returned after %v", elapsed)
	}
	// A deadline of the caller is not a cancel: it is the fixed lock sentence.
	wantStatus(t, err, 500)
	if err.Error() != lockSentence || ran {
		t.Errorf("err = %v, ran = %v", err, ran)
	}
	close(release)
	if err := <-holderDone; err != nil {
		t.Fatal(err)
	}
	if err := WithWriteLock(data, func() error { return nil }); err != nil {
		t.Fatalf("after the release: %v", err)
	}
}

// A ctx that is already cancelled never takes the lock, never creates the lock file.
func TestWriteLockContextAlreadyCancelled(t *testing.T) {
	data := filepath.Join(tempDir(t), "data")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	ran := false
	if err := WithWriteLockContext(ctx, data, func() error { ran = true; return nil }); !errors.Is(err, context.Canceled) || ran {
		t.Errorf("err = %v, ran = %v", err, ran)
	}
	if _, err := os.Stat(data); !os.IsNotExist(err) {
		t.Errorf("the data folder was created: %v", err)
	}
}

// The wait has a hard limit: another process that never lets go gives the fixed 500, not a hang. The limit is
// injected short here; the shipped one is lockWaitLimit.
func TestWriteLockWaitLimit(t *testing.T) {
	data := tempDir(t)
	holdFlock(t, data)
	ran := false
	started := time.Now()
	_, err := withWriteLock(context.Background(), data, 150*time.Millisecond, func() (int, error) { ran = true; return 1, nil })
	if elapsed := time.Since(started); elapsed < 150*time.Millisecond || elapsed > time.Second {
		t.Errorf("gave up after %v, want about 150 ms", elapsed)
	}
	wantStatus(t, err, 500)
	if err.Error() != lockSentence || ran {
		t.Errorf("err = %v, ran = %v", err, ran)
	}
	if lockWaitLimit != 30*time.Second {
		t.Errorf("shipped wait limit %v, want 30 s", lockWaitLimit)
	}
}
