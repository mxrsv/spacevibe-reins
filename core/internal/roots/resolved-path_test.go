package roots

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The deepest existing ancestor is resolved, the rest appended (Roots.swift:104-117).
func TestResolvedPathMissingLeafBehindSymlink(t *testing.T) {
	h := newTempHome(t)
	target := h.url("target")
	if err := os.Mkdir(target, 0o755); err != nil {
		t.Fatal(err)
	}
	link := h.url("link")
	if err := os.Symlink(target, link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	cases := []struct{ in, want string }{
		{link, target},
		{filepath.Join(link, "a"), filepath.Join(target, "a")},
		{filepath.Join(link, "a", "b", "c"), filepath.Join(target, "a", "b", "c")},
		{filepath.Join(link, "x", "..", "y"), filepath.Join(target, "y")}, // lexical clean first, like standardizedFileURL
	}
	for _, c := range cases {
		if got := ResolvedPath(c.in); got != c.want {
			t.Errorf("ResolvedPath(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// realpath(3) fails on a dangling link, so the link name is kept as a missing leaf.
func TestResolvedPathDanglingLinkIsAMissingLeaf(t *testing.T) {
	h := newTempHome(t)
	dangling := h.url("dangling")
	if err := os.Symlink(h.url("nowhere"), dangling); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	if got := ResolvedPath(dangling); got != dangling {
		t.Errorf("got %q, want %q", got, dangling)
	}
}

func TestResolvedPathRelativeBecomesAbsolute(t *testing.T) {
	if got := ResolvedPath("some/missing/path"); !filepath.IsAbs(got) || !strings.HasSuffix(got, filepath.Join("some", "missing", "path")) {
		t.Errorf("got %q", got)
	}
}

// H4: realpath(3) on a case-insensitive volume returns the stored spelling for mixed-case input, and
// so must the port. Expected values were produced by realpath(3) from a Swift script on APFS.
func TestResolvedPathStoredSpelling(t *testing.T) {
	h := newTempHome(t)
	if err := os.MkdirAll(h.url("MixedCase/SubDir"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(h.url("mixedcase")); err != nil {
		t.Skip("volume is case-sensitive: spelling is part of the name")
	}
	cases := []struct{ in, want string }{
		{h.url("mixedcase/subdir"), h.url("MixedCase/SubDir")},
		{h.url("MIXEDCASE"), h.url("MixedCase")},
		{h.url("mixedcase/Missing/x"), h.url("MixedCase/Missing/x")}, // missing tail keeps the caller's spelling
	}
	for _, c := range cases {
		if got := ResolvedPath(c.in); got != c.want {
			t.Errorf("ResolvedPath(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestIsUnder(t *testing.T) {
	cases := []struct {
		path, dir string
		want      bool
	}{
		{"/a/b", "/a/b", true},
		{"/a/b/c", "/a/b", true},
		{"/a/bc", "/a/b", false},
		{"/a", "/a/b", false},
		{"/a/b", "/", true},
	}
	for _, c := range cases {
		if got := isUnder(c.path, c.dir); got != c.want {
			t.Errorf("isUnder(%q, %q) = %v", c.path, c.dir, got)
		}
	}
}
