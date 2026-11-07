package goldentest

import "testing"

// AssertCanonicalEqual compares two JSON trees as canonical bytes. On a difference it fails the test with a
// unified diff of the canonical text (labelled want and got); on success it logs the canonical SHA-256, so a
// run leaves a fingerprint of what was compared. Normalize both sides first (HomeToken) and build the same
// named projection on each.
func AssertCanonicalEqual(tb testing.TB, name string, want, got any) {
	tb.Helper()
	wantBytes, err := Canonical(want)
	if err != nil {
		tb.Fatalf("%s: cannot write the expected side: %v", name, err)
	}
	gotBytes, err := Canonical(got)
	if err != nil {
		tb.Fatalf("%s: cannot write the actual side: %v", name, err)
	}
	if string(wantBytes) != string(gotBytes) {
		tb.Fatalf("%s: canonical bytes differ\n%s", name, UnifiedDiff(name+" (want)", name+" (got)", string(wantBytes), string(gotBytes)))
	}
	sum, _ := CanonicalSHA256(want)
	tb.Logf("%s: canonical sha256 %s (%d bytes)", name, sum, len(wantBytes))
}

// AssertCaseCount fails the test when a golden test ran no cases. An unloaded or empty golden must not
// pass with zero comparisons (as MutateTests.swift:16-21 did). atLeast is the smallest acceptable count, at
// least 1.
func AssertCaseCount(tb testing.TB, name string, count, atLeast int) {
	tb.Helper()
	atLeast = max(atLeast, 1)
	if count < atLeast {
		tb.Fatalf("%s: ran %d cases, need at least %d", name, count, atLeast)
	}
	tb.Logf("%s: %d cases", name, count)
}
