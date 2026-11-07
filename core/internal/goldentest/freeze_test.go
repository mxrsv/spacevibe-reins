package goldentest

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// freezeDirEnv points TestFreezeSHA256SUMS at another fixtures folder. It exists to prove the check fails on a
// scratch copy with one byte flipped (G1.10 verify); leave it unset otherwise.
const freezeDirEnv = "GOLDENTEST_FREEZE_DIR"

// The frozen goldens and the .zst fixtures must match core/testdata/fixtures/SHA256SUMS, like `shasum -c`
// (P0.4, SV5). The home tree is frozen by the manifest digest (TestFixtureDigestMatchesCommittedTree).
func TestFreezeSHA256SUMS(t *testing.T) {
	dir := os.Getenv(freezeDirEnv)
	if dir == "" {
		var err error
		if dir, err = FixturesDir(); err != nil {
			t.Fatal(err)
		}
	}
	problems, err := VerifyChecksums(dir, "SHA256SUMS", "golden", "zst")
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range problems {
		t.Errorf("freeze broken: %s", p)
	}
	data, _ := os.ReadFile(filepath.Join(dir, "SHA256SUMS"))
	AssertCaseCount(t, "frozen files", strings.Count(string(data), "\n"), 14)
}

func TestFreezeCheckDetectsEachBreak(t *testing.T) {
	dir := t.TempDir()
	write := func(rel, text string) {
		t.Helper()
		must(t, os.MkdirAll(filepath.Join(dir, filepath.Dir(rel)), 0o755))
		must(t, os.WriteFile(filepath.Join(dir, rel), []byte(text), 0o644))
	}
	// sha256("abc") and sha256("") are well-known vectors.
	const abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	write("golden/a.json", "abc")
	write("SHA256SUMS", abc+"  golden/a.json\n")
	if p, err := VerifyChecksums(dir, "SHA256SUMS", "golden"); err != nil || len(p) != 0 {
		t.Fatalf("intact: %v %v", p, err)
	}

	write("golden/a.json", "abd")
	expectProblem(t, dir, "golden/a.json: checksum differs")
	write("golden/a.json", "abc")

	write("golden/new.json", "x")
	expectProblem(t, dir, "golden/new.json: not listed in SHA256SUMS")
	must(t, os.Remove(filepath.Join(dir, "golden/new.json")))

	must(t, os.Remove(filepath.Join(dir, "golden/a.json")))
	expectProblem(t, dir, "golden/a.json: missing or unreadable")
	write("golden/a.json", "abc")

	write("SHA256SUMS", abc+"  ../outside\nnot a line\n")
	expectProblem(t, dir, "line 1: malformed")
	expectProblem(t, dir, "line 2: malformed")

	write("SHA256SUMS", abc+" *golden/a.json\n") // shasum's binary-mode marker
	if p, _ := VerifyChecksums(dir, "SHA256SUMS", "golden"); len(p) != 0 {
		t.Errorf("binary marker: %v", p)
	}
	if _, err := VerifyChecksums(dir, "NOPE", "golden"); err == nil {
		t.Error("a missing sums file must be an error")
	}
}

func expectProblem(t *testing.T, dir, want string) {
	t.Helper()
	problems, err := VerifyChecksums(dir, "SHA256SUMS", "golden")
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range problems {
		if p == want {
			return
		}
	}
	t.Errorf("want problem %q, got %v", want, problems)
}
