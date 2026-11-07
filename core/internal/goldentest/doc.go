// Package goldentest is the shared harness of the golden tests (plan G1.10, parity method C1/Q1). It is
// test-support code that lives as a normal package so other packages' tests can import it; production code
// must not.
//
// It ports the fixture side of Tests/ReinsCoreTests/Support/FixtureHome.swift and FixtureHomeTests.swift:
//
//   - Materialize builds the frozen home tree at CanonicalRoot with the same staging, rename and stamp
//     protocol as FixtureHome.materialize, so a Go run and a Swift run share one tree safely.
//   - Canonical writes a JSON tree the way every golden is compared: sorted keys, JavaScript number text,
//     2-space indent, no HTML escaping.
//   - HomeToken replaces the root path with $HOME in keys and values.
//   - UnifiedDiff and AssertCanonicalEqual report a mismatch as a unified diff; AssertCaseCount refuses a
//     golden test that ran zero cases.
//   - FindLeaks, LeakNeedles and VerifyChecksums back the S-R2 leak guard and the SHA256SUMS freeze check.
//
// Fixtures live in core/testdata/fixtures and are never edited (SV5).
package goldentest
