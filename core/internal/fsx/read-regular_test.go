package fsx

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReadRegularCapAndKinds(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "f")
	if err := os.WriteFile(file, []byte(strings.Repeat("x", 10)), 0o600); err != nil {
		t.Fatal(err)
	}
	if data, err := ReadRegular(file, 10); err != nil || len(data) != 10 {
		t.Fatalf("exactly the cap: %d bytes, %v", len(data), err)
	}
	if _, err := ReadRegular(file, 9); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("one byte over the cap: %v", err)
	}
	if _, err := ReadRegular(dir, 10); !errors.Is(err, ErrNotRegular) {
		t.Fatalf("a folder: %v", err)
	}
	if _, err := ReadRegular(filepath.Join(dir, "missing"), 10); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("a missing file: %v", err)
	}
	link := filepath.Join(dir, "link")
	if err := os.Symlink(file, link); err == nil {
		if data, err := ReadRegular(link, 10); err != nil || len(data) != 10 {
			t.Fatalf("a link to a regular file is followed: %v", err)
		}
	}
}

func TestPathPresence(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "f")
	if err := os.WriteFile(file, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]Presence{
		file:                          Present,
		dir:                           Present,
		filepath.Join(dir, "missing"): Missing,
		filepath.Join(file, "below"):  Missing, // ENOTDIR
	} {
		if got := PathPresence(path); got != want {
			t.Errorf("%s: %d, want %d", path, got, want)
		}
	}
}
