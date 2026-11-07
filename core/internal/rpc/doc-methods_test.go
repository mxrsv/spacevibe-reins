package rpc_test

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/proc"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/rpc"
	"spacevibe.dev/core/internal/rpc/methods"
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
	if !slices.Equal(doc, rpc.AllMethods) {
		t.Fatalf("doc table is %v, AllMethods is %v", doc, rpc.AllMethods)
	}
	seen := map[string]bool{}
	for _, n := range rpc.AllMethods {
		if seen[n] {
			t.Fatalf("AllMethods lists %q twice", n)
		}
		seen[n] = true
	}

	// A bare server registers only initialize; the domain methods are added by methods.Register.
	bare := rpc.NewRegistry()
	rpc.NewServer(bare, rpc.Options{})
	if got := bare.Methods(); !slices.Equal(got, []string{rpc.MethodInitialize}) {
		t.Errorf("a fresh server registers only initialize, got %v", got)
	}

	// The wired registry must equal AllMethods and the doc table: nothing missing, nothing extra.
	dir := t.TempDir()
	cfg := config.Config{Test: true, UserHome: dir, ClaudeConfigDir: filepath.Join(dir, ".claude"),
		CodexHome: filepath.Join(dir, ".codex"), Home: filepath.Join(dir, ".spacevibe")}
	r, err := roots.Resolve(cfg, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	wired := rpc.NewRegistry()
	rpc.NewServer(wired, rpc.Options{})
	svc := methods.New(cfg, r, proc.NewFixture(nil, nil, nil, 0), nil)
	defer svc.Close()
	svc.Register(wired)
	want := slices.Sorted(slices.Values(rpc.AllMethods))
	if got := wired.Methods(); !slices.Equal(got, want) {
		t.Errorf("registered %v, want exactly AllMethods %v", got, want)
	}
	for _, n := range wired.Methods() {
		lower := strings.ToLower(n)
		if strings.HasPrefix(lower, "statusline") || strings.Contains(lower, "capture") || strings.Contains(lower, "addhook") {
			t.Errorf("%q must not be an RPC method", n)
		}
	}
}
