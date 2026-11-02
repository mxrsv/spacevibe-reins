# Reins: Tokens tab

Spec: [2026-11-02-reins.md](../specs/2026-11-02-reins.md) (Interface: Tokens; Scope: Tab: Tokens; acceptance criteria AC5, AC6, AC8, AC9).
Parent plan: [the SwiftUI plan](2026-11-02-reins-swiftui.md), whose packaging and cut-over phases still apply.
Mock: `mocks/tokens-board/index.html` with synthetic data, plus `shot-dark.png` and `shot-light-price.png`, so a cloud run can see the target. The owner's copy with real numbers stays outside git at `~/scratch/spacevibe-reins/tokens-d-board.html` (`AGENTS.md` R2, S-R2).
Status: direction accepted by the owner on 2026-11-03; no Swift written. Started 2026-11-03.

## Approach

A new engine module folds token usage out of the same logs the other scans read and keeps a rollup that outlives them; a new tab draws it.

```
Sources/ReinsCore/  TokenLedger (fold, persist, merge), TokenLedgerQuery (series, ranking, cost)
Sources/Reins/TokenUsage/  TokensTab, TokensModel, one file per card (Sources/Reins/Tokens/ already holds the design tokens)
Sources/Reins/Components/  FilterChip gains a dismiss variant; ProviderMark
Tests/ReinsCoreTests/  TokenLedgerTests against TempHome
```

Facts this plan rests on, read 2026-11-03:

- `ActivityFold.claudeAssistant` keeps the largest usage per `model:messageId` because streaming blocks repeat it. `ActivityFold.codexUsage` skips repeated totals, trusts `last_token_usage` and subtracts cached tokens from input. Both are private to Activity and write into its state, so T1 lifts the counting into a function both call, with Activity's goldens as the guard against a behaviour change.
- `UsageScanCache` drops an entry when its log disappears (`UsageScanner` rebuilds from the files present), so the rollup cannot live there. `Roots.data` is the right folder.
- `projectName(_:hint:memo:)` in `SessionTitles.swift` already handles worktree slugs. TokenTracker's project queue covers about 22% of tokens on this Mac; Reins attributes from the log's `cwd`, so its coverage is unmeasured until T1 runs.
- `TabRegistry.makeTabs()` is the one place to add a tab. `ReinsTab` supplies the title, hints and palette entries.
- `Pricing.models` is a Swift literal that a test compares with `core/pricing.json`.

## Decisions made in this plan (reversible)

- **Buckets are UTC hours; a day is computed from them in the machine's time zone when read.** A rollup stored by local day would be wrong after a time zone change.
- **The ledger keeps one row set per log file**, keyed by path with the same `<size>:<mtime>` stamp as the usage cache. A changed log replaces its own rows; a missing log keeps them. Rows hold hour, CLI, model, project name and four counts, never log text. File: `token-ledger.json` under `Roots.data`, mode 0600, written atomically.
- **A corrupt ledger is moved aside and reported, never silently replaced by an empty one**, because it can hold days no log has any more. This is the opposite of the usage cache, which may be thrown away.
- **Plain SwiftUI views for the charts, not Swift Charts.** Every column is a keyboard-selectable control and the axis cut needs a notch and a printed value; a stack of shapes does this in fewer lines. Swift Charts under Command Line Tools is also unverified here.
- **"Sessions", not "conversations".** TokenTracker's `conversation_count` sums per model and hour (10,887 in 30 days from about 1,500 Claude logs on this Mac), so the mock's figure is inflated. Reins counts distinct session files per bucket. This number is not part of AC8.
- **Marks are converted once into SwiftUI shapes or bundled the way `spacevibe-board/Sources/SpaceVibeBoard/UI/ProviderLogo.swift` does**; T5 picks the shorter path; a cloud run without that repo converts the paths to SwiftUI shapes. The paths are already in `mocks/tokens-board/mock-shell/tokens-logos.js`, copied from `spacevibe-bench/public/brand/providers/{anthropic,openai}.svg` and `spacevibe-board/Resources/Brand/codex-blossom-white.svg`, so a cloud run needs neither repo.

## Where each task runs

This is the one plan for the whole tab. The owner runs it on the cloud; what cannot run there is marked.

| Tasks | Where | Why |
| --- | --- | --- |
| T0 | This Mac, once | A cloud token may not be allowed to push workflow files, and the owner approves the macOS minutes |
| T1 to T4 | Cloud | `ReinsCore` is Foundation only. A Linux build is unverified (parent plan S0.6), so CI from T0 is the check that counts |
| T5, T6 | Cloud, only after T0 | SwiftUI compiles on macOS only. The cloud agent pushes and reads the CI result and screenshots instead of building locally |
| T7 | This Mac | It reads the owner's real logs, which never leave the machine |
| T8 | The owner | Eyes on the built app |

## Tasks

- [ ] T0 macOS CI. `.github/workflows/swift.yml` on pushes to `claude/**` and PRs: `macos` runner, `swift build`, `scripts/test.sh`, `scripts/build-app.sh` without signing, and Tokens screenshots from the fixture home uploaded as an artifact. Verify with one real run, and record the toolchain it used against B1 to B4. Needs the owner's approval: it pushes a workflow and uses paid macOS minutes on this private repo.
- [x] T1 Fold. Lift Claude and Codex usage counting out of `ActivityFold` into a shared function with Activity's goldens unchanged, then fold a log into hour, CLI, model, project and session rows, reading `.jsonl` and `.jsonl.zst` through `LogFiles`. Tests against `TempHome`: repeated streaming blocks, repeated Codex totals, Codex input without cached tokens, a sidechain, an unknown model, a line with no timestamp.
  Answered 2026-11-03 on the owner's Mac (read-only, counts only): of 1,805 Claude logs (880 under `subagents/`), 150 of 76,977 messages repeat across files, in 36 files, 20.9M of 15.2B tokens (0.14%). The per-file ledger stays and this small overcount is accepted, because it is inside AC8's 1% and spanning files would keep every message id forever. Fold `subagents/` logs too: they are about half the files.
  Done in code: [TokenCount.swift](../../Sources/ReinsCore/TokenCount.swift) holds `ClaudeUsageCounter` and `CodexUsageCounter`, which [ActivityFold](../../Sources/ReinsCore/ActivityFold.swift) now calls; its JavaScript-style JSON helpers moved to [JSONValueJS.swift](../../Sources/ReinsCore/JSONValueJS.swift). [TokenFold](../../Sources/ReinsCore/TokenFold.swift) parses only assistant records with usage and the worktree record (Claude) or `session_meta`, `turn_context` and `token_count` (Codex). A line with no timestamp takes the last hour seen, or the first one after it, or the log's mtime. One addition to the four counts: `cacheWrite1h`, the one-hour part of cache write, so cost prices it like Activity does; it is never shown as a kind. Tests: [TokenFoldTests](../../Tests/ReinsCoreTests/TokenFoldTests.swift).
  Linux (swift 6.2.4 in Docker, temporary manifest outside the commit with CZstd, ReinsCore and the tests, plus a CryptoKit shim for two test files): `swift test` → `Test run with 268 tests in 27 suites`, 9 issues, every one also failing on unchanged `main` there (permission tests run as root, `ps` start time); Activity goldens pass. macOS CI run [41502113947](https://github.com/mxrsv/spacevibe-reins/actions/runs/41502113947) on `740f549` (macos-15, Xcode 16.4, Swift 6.1.2): `scripts/test.sh` → `✔ Test run with 277 tests passed after 14.065 seconds.`, `build-app.sh` → `minos 15.0`.
- [x] T2 Ledger (AC9). Load, merge, save per the decisions above; a scan version forces a refold of files still present and keeps rows of files that are gone. Tests: deleting a counted log and rescanning leaves every past day unchanged; a corrupt file is moved aside and reported; the file is mode 0600; `REINS_TEST=1` refuses the real home. Runs in an actor off the main thread with progress, like `UsageScanner`.
  Done in code: [TokenLedger.swift](../../Sources/ReinsCore/TokenLedger.swift) (entry, key, merge, load and save) and [TokenLedgerScanner](../../Sources/ReinsCore/TokenLedgerScanner.swift) (actor, progress every 20 logs). Two refinements of the decisions above: the key is `<cli>/<path under the CLI's log folder without .jsonl or .jsonl.zst>`, because Codex compresses older rollouts and a key on the full path would count such a session twice; and a changed log at the same scan version keeps, per hour and model, the larger of the old and new counts, so "a rescan never lowers a past day" holds even for a log rewritten smaller (a new scan version replaces the entry instead). An unreadable ledger is moved to `token-ledger.unreadable-<UTC time>.json` and reported in `TokenScanResult.movedAside`; one that cannot be opened at all (not a regular file, or no permission) is left alone and `notSaved` says so. `LogFiles.stamp(of:)` is now the one stamp both the usage cache and the ledger use. Tests: [TokenLedgerTests](../../Tests/ReinsCoreTests/TokenLedgerTests.swift).
  Linux (same temporary manifest): `swift test` → `Test run with 278 tests in 28 suites`, the same 9 environment issues as `main`. macOS CI run [41502782869](https://github.com/mxrsv/spacevibe-reins/actions/runs/41502782869) on `0c2f2b3`: `✔ Test run with 287 tests passed after 13.735 seconds.`, `minos 15.0`.
- [ ] T3 Query. Series by day (last 30), week (last 12), month (all); ranking of models and projects; four kinds per CLI; cost from `Pricing` with priced subtotal and unpriced tokens kept apart, for any scope of day, model or project. A model with no price yields no cost, never 0. The date counting starts from, per CLI. Unit tests with a fixed clock and a fixed time zone, including a day that crosses UTC.
- [ ] T4 Price table. Add the logged models that have none (`gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.5`, `claude-opus-5`, `claude-fable-5-1`, `claude-haiku-5-5` and the rest of the 4.21B of 24.57B tokens measured 2026-11-03) to `Pricing.swift` and `core/pricing.json` together, each with its source and `fetchedAt`. A model that needs tier information stays unpriced on purpose. Prices come from the vendors' pages at the time of the task, not from memory or from TokenTracker. If a golden changes, run `node scripts/make-golden.mjs` and read the diff.
- [ ] T5 Shared pieces. Dismiss variant of `FilterChip` (a real button with a spoken label), `ProviderMark`, and any `ReinsFont` steps the size order needs (lead total, figure per CLI, card leader) added to `Metrics.swift`, not as local literals.
- [ ] T6 Screen. `TokensTab` in `TabRegistry`, so `⌘4` follows. Build the Board from the spec's Interface list and the mock: tools row, summary, By day with the axis cut, Models, Projects, Cache reuse, Estimated cost with the price popover, Days with rows that open. Keyboard: `←` `→` move the day, `↵` opens its token kinds, `Esc` clears the scope; visible focus; VoiceOver labels on columns and bars; reduced motion. Palette entries for period, measure and clear scope. States: first scan with progress, no logs, no price, a CLI with nothing in scope, ledger moved aside. No file over 400 lines. Screenshots from the fixture home, dark and light: the CI artifact on the cloud, `~/scratch/spacevibe-reins/shots/swift-tokens/` on the Mac. Compare them with the two PNGs in `mocks/tokens-board/` before ticking this.
- [ ] T7 Parity (AC8, on the owner's Mac, read-only). Compare with `~/.tokentracker/tracker/queue.jsonl` per local day, CLI and field for the last 30 full days. Explain or fix each difference above 1%, including the 10 duplicated (source, model, hour) keys in that file. Record the summary here; per-day output stays out of git. Start from this gap, measured 2026-11-03: the largest usage per Claude message id sums to 15.2B, while TokenTracker's queue says 21.0B for Claude. Hypothesis, unverified: TokenTracker counts repeated streaming blocks. Record how long the first scan took on the owner's 8 GB of logs; if it blocks use, fix it in this task.
- [ ] T8 Owner eye approval (AC6). Open the built app and the screenshots in one batch, after T1 to T7. This is the only eye gate in this plan. When it passes, delete `mocks/tokens-board/` and its line in `AGENTS.md`.

T0 first for anything UI. T1 to T3 run in order. T4 and T5 are independent. T6 needs T3 and T5. T7 needs T6's engine wiring, not its polish.

## Verification

- `scripts/test.sh`: read the `Test run with N tests ... passed` line, N above 0, on macOS. Never bare `swift test` on the Mac (B2). A Linux result alone does not tick a task that touches `Sources/Reins`.
- `scripts/build-app.sh` prints `minos 15.0` (B1).
- `git status --porcelain` shows no real names or numbers in fixtures (S-R2).

## Acceptance map

| AC | Covered by |
| --- | --- |
| AC5 all four tabs offline | T6, parent plan S8.1 |
| AC6 owner approves the UI by eye | T8 |
| AC8 Tokens matches TokenTracker | T7 |
| AC9 history survives a deleted log | T2 |

## Action needed from the owner

- T7 reads the real logs, so it runs on this Mac with the owner's say-so in that session.
- T8 eye approval.
- Uninstalling TokenTracker is the owner's step, after T7 and T8. It also installed hooks and a Codex `notify` entry; check those go with it.

## Handoff

- Checkout: `main`. Another session is working on the parent plan in the same checkout, so commit with `git commit -- <paths>` and read `git status` first: `4b45a25` swept that session's spec edits into a Tokens commit.
- Cloud run: routine `trig_01RkCKKMMrxNXKw5pXcK3zRP` does T1 to T4 once on 2026-11-03 at 01:07 Asia/Saigon, on branch `claude/reins-tokens-engine` with a PR. **A later cloud run continues from that branch if it exists, in the same PR**, instead of starting again from `main`.
- Remaining: T1 to T8.

`/goal` Build the Reins Tokens tab per docs/specs/2026-11-02-reins.md: complete docs/plans/2026-11-03-reins-tokens.md tasks T1 to T6 on branch claude/reins-tokens-engine, continuing it if it exists, so that AC9 holds and the Board matches mocks/tokens-board/ in the macOS CI build and its screenshots, recording each task's evidence under it and opening one PR; stop and report if T0's workflow is missing or CI cannot build, and never read real logs, merge to main or release.
