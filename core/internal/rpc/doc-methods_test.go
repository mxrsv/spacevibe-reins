package rpc

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

const protocolDoc = "../../../docs/internals/core-protocol.md"

// docMethods returns the backticked names in the first column of the method table under
// "## Methods".
func docMethods(t *testing.T) []string {
	t.Helper()
	b, err := os.ReadFile(protocolDoc)
	if err != nil {
		t.Fatal(err)
	}
	row := regexp.MustCompile("^\\| `([^`]+)` \\|")
	var names []string
	in := false
	for _, line := range strings.Split(string(b), "\n") {
		switch {
		case strings.HasPrefix(line, "## "):
			in = line == "## Methods"
		case in:
			if m := row.FindStringSubmatch(line); m != nil {
				names = append(names, m[1])
			}
		}
	}
	return names
}

func TestDocMethodTable(t *testing.T) {
	doc := docMethods(t)
	if len(doc) != len(AllMethods) {
		t.Fatalf("doc table has %d methods, AllMethods has %d", len(doc), len(AllMethods))
	}
	for i := range doc {
		if doc[i] != AllMethods[i] {
			t.Fatalf("doc row %d is %q, AllMethods has %q", i, doc[i], AllMethods[i])
		}
	}
	seen := map[string]bool{}
	for _, n := range AllMethods {
		if seen[n] {
			t.Fatalf("AllMethods lists %q twice", n)
		}
		seen[n] = true
	}

	// Registered methods are a subset until the wiring tasks land; each of them then asserts
	// that the registered set equals AllMethods.
	reg := NewRegistry()
	NewServer(reg, Options{})
	known := map[string]bool{}
	for _, n := range AllMethods {
		known[n] = true
	}
	for _, n := range reg.Methods() {
		if !known[n] {
			t.Errorf("registered method %q is not in AllMethods", n)
		}
	}
	if got := reg.Methods(); len(got) != 1 || got[0] != MethodInitialize {
		t.Errorf("a fresh server registers only initialize, got %v", got)
	}
}
