package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	cases := []struct {
		name       string
		args       []string
		code       int
		out, errOu string
	}{
		{"version", []string{"--version"}, 0, "spacevibe dev\n", ""},
		{"no args", nil, 2, "", "usage:"},
		{"unknown", []string{"nope"}, 2, "", "unknown command"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var out, errb bytes.Buffer
			if got := run(c.args, &out, &errb); got != c.code {
				t.Fatalf("exit %d, want %d", got, c.code)
			}
			if c.out != "" && out.String() != c.out {
				t.Fatalf("stdout %q, want %q", out.String(), c.out)
			}
			if !strings.Contains(errb.String(), c.errOu) {
				t.Fatalf("stderr %q lacks %q", errb.String(), c.errOu)
			}
		})
	}
}
