package goldentest

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/klauspost/compress/zstd"
)

// Swift: FixtureHomeTests.swift "the committed tree is synthetic: no real home path, user name or leftover temp path"
// and "...no real path leaks" (golden). Go widens it from the home tree and one golden to every file under
// core/testdata, the compressed logs after decompression, and file names (S-R2).
func TestLeakNoRealHomeOrUserNameUnderTestdata(t *testing.T) {
	needles, err := LeakNeedles()
	if err != nil {
		t.Fatal(err)
	}
	AssertCaseCount(t, "leak needles", len(needles), 3)
	fixtures, _ := FixturesDir()
	testdata := filepath.Dir(fixtures)
	hits, err := FindLeaks(testdata, needles)
	if err != nil {
		t.Fatal(err)
	}
	for _, h := range hits {
		t.Errorf("leak: %s", h)
	}
	count := 0
	_ = filepath.WalkDir(testdata, func(_ string, d os.DirEntry, _ error) error {
		if d != nil && !d.IsDir() {
			count++
		}
		return nil
	})
	AssertCaseCount(t, "files scanned under core/testdata", count, 200)
}

func TestLeakScannerFindsPlantedNeedles(t *testing.T) {
	dir := t.TempDir()
	needles := []string{"/home/someone", "someone"}
	plant := func(rel string, data []byte) {
		t.Helper()
		path := filepath.Join(dir, rel)
		must(t, os.MkdirAll(filepath.Dir(path), 0o755))
		must(t, os.WriteFile(path, data, 0o644))
	}
	plant("clean.txt", []byte("nothing here"))
	plant("a/plain.json", []byte(`{"path":"/home/someone/x"}`))
	plant("b/by-name-only-someone.txt", []byte("clean"))
	enc, err := zstd.NewWriter(nil)
	must(t, err)
	plant("c/log.jsonl.zst", enc.EncodeAll([]byte("line /home/someone/y\n"), nil))

	hits, err := FindLeaks(dir, needles)
	must(t, err)
	got := strings.Join(hits, "\n")
	for _, want := range []string{
		"a/plain.json (bytes contains needle #0)",
		"b/by-name-only-someone.txt (name contains needle #1)",
		"c/log.jsonl.zst (decompressed bytes contains needle #0)",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing hit %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "clean.txt") {
		t.Errorf("clean.txt reported:\n%s", got)
	}
	if strings.Contains(got, "/home/someone/x") {
		t.Error("a hit quotes file content (S-R3)")
	}
}
