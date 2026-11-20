package clis

import (
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// MC-R3 acceptance: with the folders of three CLIs in a home and the binary of a fourth on a fake PATH, exactly those
// four are detected. Installed is handed a stat spy, the only way it reaches the disk, so the spy's list is every
// file access it made: stats, never a process.
func TestInstalledFindsFoldersAndBinariesByStatOnly(t *testing.T) {
	home, bin, other := t.TempDir(), t.TempDir(), t.TempDir()
	for _, folder := range []string{".one", ".two", ".three"} {
		if err := os.Mkdir(filepath.Join(home, folder), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write := func(path string, mode fs.FileMode) {
		t.Helper()
		if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 1\n"), mode); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(bin, "four"), 0o755)
	write(filepath.Join(bin, "five"), 0o644) // not executable
	if err := os.Mkdir(filepath.Join(bin, "six"), 0o755); err != nil {
		t.Fatal(err)
	}
	cases := []Descriptor{
		{ID: "one", Layout: Layout{Folder: ".one"}},
		{ID: "two", Layout: Layout{Folder: ".two"}, Binaries: []string{"two"}},
		{ID: "three", Layout: Layout{Folder: ".three"}},
		{ID: "four", Layout: Layout{Folder: ".four"}, Binaries: []string{"four"}},
		{ID: "five", Layout: Layout{Folder: ".five"}, Binaries: []string{"five"}},
		{ID: "six", Layout: Layout{Folder: ".six"}, Binaries: []string{"six"}},
		{ID: "seven", Layout: Layout{Folder: ".seven"}},
	}
	var statted []string
	spy := func(name string) (fs.FileInfo, error) {
		statted = append(statted, name)
		return os.Stat(name)
	}
	path := []string{"relative/bin", other, bin}
	var found []ID
	for _, d := range cases {
		if Installed(d, filepath.Join(home, d.Layout.Folder), path, spy) {
			found = append(found, d.ID)
		}
	}
	if want := []ID{"one", "two", "three", "four"}; !slices.Equal(found, want) {
		t.Fatalf("installed = %v, want %v", found, want)
	}
	for _, name := range statted {
		if !filepath.IsAbs(name) {
			t.Errorf("stat of a relative path %q: a relative PATH folder must be skipped", name)
		}
	}
	if !slices.Contains(statted, filepath.Join(other, "four")) || !slices.Contains(statted, filepath.Join(bin, "four")) {
		t.Errorf("PATH folders not searched in order: %v", statted)
	}
}
