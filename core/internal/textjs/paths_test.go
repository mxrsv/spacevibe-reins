package textjs

import "testing"

func TestBasenameDirname(t *testing.T) {
	// Expected values from the Swift implementation. The first two Basename rows are
	// Swift: ActivityTests.swift "text helpers behave like the JavaScript they replace".
	cases := []struct{ in, base, dir string }{
		{"/a/b/", "b", "/a"},
		{"/", "", "/"},
		{"", "", "."},
		{"//", "", "/"},
		{"///a//", "a", "//"},
		{"a", "a", "."},
		{"a/b", "b", "a"},
		{"/a", "a", "/"},
		{"a/", "a", "."},
		{"/a/b", "b", "/a"},
		{"/a//b", "b", "/a/"},
		{"a//", "a", "."},
		{"./x/", "x", "."},
		{"x/y/z/", "z", "x/y"},
		{"/hé/\U0001F600", "\U0001F600", "/hé"},
	}
	for _, c := range cases {
		if got := Basename(c.in); got != c.base {
			t.Errorf("Basename(%q) = %q, want %q", c.in, got, c.base)
		}
		if got := Dirname(c.in); got != c.dir {
			t.Errorf("Dirname(%q) = %q, want %q", c.in, got, c.dir)
		}
	}
}
