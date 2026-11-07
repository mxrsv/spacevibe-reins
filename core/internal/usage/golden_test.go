package usage

import (
	"bytes"
	"encoding/json"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/goldentest"
	"spacevibe.dev/core/internal/roots"
)

// jsonTree is v as the generic tree the canonical writer takes (numbers stay json.Number).
func jsonTree(t testing.TB, v any) any {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var out any
	if err := dec.Decode(&out); err != nil {
		t.Fatal(err)
	}
	return out
}

// fixtureRoots points every root at the shared fixture tree, with a private data folder so the scan cache
// never lands in the shared tree.
func fixtureRoots(t testing.TB) (roots.Roots, string) {
	t.Helper()
	root, err := goldentest.Materialize()
	if err != nil {
		t.Fatal(err)
	}
	env := goldentest.Env(root)
	env["SPACEVIBE_HOME"] = t.TempDir()
	cfg, err := config.LoadFrom(func(k string) string { return env[k] })
	if err != nil {
		t.Fatal(err)
	}
	realHome, err := roots.RealHome()
	if err != nil {
		t.Fatal(err)
	}
	r, err := roots.Resolve(cfg, realHome)
	if err != nil {
		t.Fatal(err)
	}
	return r, root
}

// Swift: UsageScanTests.swift "a scan of the shared fixture tree equals usage.json from the Node core"
// Projection usage-cold-warm: the encoded cold scan; a warm scan (read from the cache) must equal it. The
// result holds no path, so no home-token step is needed (and goldentest.HomeToken would turn json.Number
// values into strings).
func TestGoldenUsage(t *testing.T) {
	r, _ := fixtureRoots(t)
	scanner := NewScanner(r)
	cold := mustScan(t, scanner)
	want, err := goldentest.LoadGolden("usage")
	if err != nil {
		t.Fatal(err)
	}
	goldentest.AssertCanonicalEqual(t, "usage-cold", want, jsonTree(t, cold))
	goldentest.AssertCaseCount(t, "usage golden", cold.Files, 100)

	// The second scan reads the cache and gives the same answer.
	warm := mustScan(t, NewScanner(r))
	goldentest.AssertCanonicalEqual(t, "usage-warm", jsonTree(t, cold), jsonTree(t, warm))
	if len(loadCache(r.Data)) != cold.Files {
		t.Errorf("the cache holds %d entries, want %d", len(loadCache(r.Data)), cold.Files)
	}
}
