# Swift review fixes

Historical implementation record — accepted for delivery on 2026-11-11. Implementation: `2bd9252`.

Requirements: the six confirmed MEDIUM findings in the 2026-11-11 chat review of `ad8ea1b`; the owner authorized all fixes with "fix tất cả". No new product contract or separate spec is needed. The previous [review-fixes plan](2026-11-10-review-fixes.md) is historical and stays unchanged.

Checkout: `spacevibe-reins`, current `main`. Preserve the concurrent accessibility work and `.playwright-mcp/`. The owner authorized pushing current `main` on 2026-11-11 after the warning captures were presented. No merge or release is authorized.

## Approach and acceptance

- [x] F1: capture the Rules submission scope before the asynchronous shape check; a delayed check followed by a scope switch must still write the original scope.
- [x] F2: preserve display row keys through reload by matching surviving core member ids. Keep the existing grouping semantics and core keys for usage. Removing a user/plugin duplicate must keep the surviving neighbour current; a later Remove must not target another skill.
- [x] F3: guard menu navigation against removed entries; Right on an expired index is a no-op and subsequent movement works.
- [x] F4: derive a window's current state from both its wire flag and reset timestamp at display time, across classic and v5 Limits. An expired cached snapshot shows unknown and leaves recommendations/reset lists.
- [x] F5: recover when the helper loses its usage state between the scan reply and the follow-up rows read; do not rescan endlessly on an actual failed scan.
- [x] F6: preserve cached data after refresh failure, with a visible warning and Retry on Agents/Rules and classic Loadout. First-read failures keep their existing empty state.

## Verification and delivery

- [x] Extend the existing focused test suites with the reproduced transitions; use synthetic data only.
- [x] Run `scripts/test.sh` (Go vet/tests, fixture hashes, nonzero Swift test count) and the build gate. Never bare `swift test`.
- [x] Reuse `swift-reviewer` once after implementation; resolve confirmed in-scope findings and rerun affected checks.
- [x] Capture and inspect synthetic stale-read warning states; distill/clarify the copy, then open the main capture for owner eye approval. No Computer Use or dev server.
- [x] Update relevant living documentation, check diffs and links, commit only owned paths.
- [x] Owner delivery go-ahead: "push" on 2026-11-11 after the final warning captures were presented and opened. This authorizes delivery; it is not a claim that native interaction or VoiceOver was tested.

## Evidence and handoff

2026-11-11: baseline review reproduced all six defects with actual Swift functions/models and fake Core responses. Baseline build passed; `scripts/test.sh` passed 527 tests in 54 suites and 24 Go packages. UI and native input were not exercised in that review. Implementation started on `ad8ea1b` with concurrent accessibility edits already present.

2026-11-11 implementation: F1–F6 code and regressions added. The pre-fix regression run failed 5 tests in 4 suites with 19 issues, matching the original symptoms. The post-fix focused run exposed an invalid new test fixture (missing Global scope), corrected in the test helper. The first full gate stopped in unchanged Go test `TestCodexThreadsLsofFailureMarksLocksUnknown`; it then passed 3/3 isolated runs. The full `GOFLAGS=-p=1 scripts/test.sh` run passed: all 24 Go packages, fixture hashes, and "Test run with 537 tests in 54 suites passed after 5.749 seconds." This includes the accessibility tests from the concurrent task. `swift-reviewer` returned APPROVE with no remaining HIGH/MEDIUM finding in this diff.

2026-11-11 final verification: `scripts/build-app.sh` passed with app `minos 15.0`, helper `minos 12.0`, valid signature and designated requirement. Synthetic `skills`, `rules` (v5) and classic `loadout` screenshot runs all passed, including their write/Undo assertions. Warning captures were inspected in dark/light and at 960px: the warning and Try again fit. Copy was distilled/clarified to one cached-reading fact, the core's reason and one recovery action. Local markdown links and owned-path diff checks passed. Captures: `~/scratch/spacevibe-reins/2026-11-11-swift-review-fixes/`; main review artifact: `warning-states.html`. Native interaction/VoiceOver and update E2E were not run. A separate narrow Skills layout issue (Codex label wrapping in `Components/DetailPane.swift:134`) was reported once and left outside this scope.

Delivery: the concurrent accessibility task committed `f8ae3a2` on `main`; its files are preserved. This task commits its implementation and verification record together, by explicit owned paths, on top of that revision. The code and verification are complete in `2bd9252`. The owner then instructed "push" on 2026-11-11 after the warning captures were presented; deliver current `main` to its existing upstream without another approval round. Merge and release remain outside the request.

/goal Fix all six confirmed Swift review findings from 2026-11-11, preserve unrelated accessibility work, pass focused regressions and scripts/test.sh plus build, complete swift-reviewer follow-up, inspect synthetic warning captures, commit only this task's verified files, and push current main following the owner's 2026-11-11 delivery go-ahead; do not merge or release.
