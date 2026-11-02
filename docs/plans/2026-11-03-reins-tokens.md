# Reins: Tokens tab

Spec: [2026-11-02-reins.md](../specs/2026-11-02-reins.md) (Interface: Tokens; Scope: Tab: Tokens; acceptance criteria AC5, AC6, AC8, AC9).
Parent plan: [the SwiftUI plan](2026-11-02-reins-swiftui.md), whose packaging and cut-over phases still apply.
Mock, outside the repo: `~/scratch/spacevibe-reins/tokens-d-board.html`, with `mock-shell/tokens.css` and `mock-shell/tokens.js`. It holds real numbers from the owner's Mac, so it stays out of git (`AGENTS.md` R2, S-R2).
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
- **Marks are converted once into SwiftUI shapes or bundled the way `spacevibe-board/Sources/SpaceVibeBoard/UI/ProviderLogo.swift` does**; T5 reads that file and picks the shorter path. Sources: `spacevibe-bench/public/brand/providers/{anthropic,openai}.svg`, `spacevibe-board/Resources/Brand/codex-blossom-white.svg`. Copying a file reads those repos; it does not write to them (workspace X1, X2).

## Tasks

- [ ] T1 Fold. Lift Claude and Codex usage counting out of `ActivityFold` into a shared function with Activity's goldens unchanged, then fold a log into hour, CLI, model, project and session rows, reading `.jsonl` and `.jsonl.zst` through `LogFiles`. Tests against `TempHome`: repeated streaming blocks, repeated Codex totals, Codex input without cached tokens, a sidechain, an unknown model, a line with no timestamp. **First find out whether a resumed Claude session repeats earlier messages across files:** if it does, deduplication must span files and the per-file design changes. Record the answer here.
- [ ] T2 Ledger (AC9). Load, merge, save per the decisions above; a scan version forces a refold of files still present and keeps rows of files that are gone. Tests: deleting a counted log and rescanning leaves every past day unchanged; a corrupt file is moved aside and reported; the file is mode 0600; `REINS_TEST=1` refuses the real home. Runs in an actor off the main thread with progress, like `UsageScanner`.
- [ ] T3 Query. Series by day (last 30), week (last 12), month (all); ranking of models and projects; four kinds per CLI; cost from `Pricing` with priced subtotal and unpriced tokens kept apart, for any scope of day, model or project. A model with no price yields no cost, never 0. The date counting starts from, per CLI. Unit tests with a fixed clock and a fixed time zone, including a day that crosses UTC.
- [ ] T4 Price table. Add the logged models that have none (`gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.5`, `claude-opus-5`, `claude-fable-5-1`, `claude-haiku-5-5` and the rest of the 4.21B of 24.57B tokens measured 2026-11-03) to `Pricing.swift` and `core/pricing.json` together, each with its source and `fetchedAt`. A model that needs tier information stays unpriced on purpose. Prices come from the vendors' pages at the time of the task, not from memory or from TokenTracker. If a golden changes, run `node scripts/make-golden.mjs` and read the diff.
- [ ] T5 Shared pieces. Dismiss variant of `FilterChip` (a real button with a spoken label), `ProviderMark`, and any `ReinsFont` steps the size order needs (lead total, figure per CLI, card leader) added to `Metrics.swift`, not as local literals.
- [ ] T6 Screen. `TokensTab` in `TabRegistry`, so `⌘4` follows. Build the Board from the spec's Interface list and the mock: tools row, summary, By day with the axis cut, Models, Projects, Cache reuse, Estimated cost with the price popover, Days with rows that open. Keyboard: `←` `→` move the day, `↵` opens its token kinds, `Esc` clears the scope; visible focus; VoiceOver labels on columns and bars; reduced motion. Palette entries for period, measure and clear scope. States: first scan with progress, no logs, no price, a CLI with nothing in scope, ledger moved aside. No file over 400 lines. Screenshots to `~/scratch/spacevibe-reins/shots/swift-tokens/` from the fixture home, dark and light.
- [ ] T7 Parity (AC8, on the owner's Mac, read-only). Compare with `~/.tokentracker/tracker/queue.jsonl` per local day, CLI and field for the last 30 full days. Explain or fix each difference above 1%, including the 10 duplicated (source, model, hour) keys in that file. Record the summary here; per-day output stays out of git. Record how long the first scan took on the owner's 8 GB of logs; if it blocks use, fix it in this task.
- [ ] T8 Owner eye approval (AC6). Open the built app and the screenshots in one batch, after T1 to T7. This is the only eye gate in this plan.

T1 to T3 run in order. T4 and T5 are independent. T6 needs T3 and T5. T7 needs T6's engine wiring, not its polish.

## Verification

- `scripts/test.sh`: read the `Test run with N tests ... passed` line, N above 0. Never bare `swift test` (B2).
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
- Remaining: T1 to T8.

`/goal` Build the Reins Tokens tab per docs/specs/2026-11-02-reins.md: complete docs/plans/2026-11-03-reins-tokens.md tasks T1 to T6 so that AC9 holds under scripts/test.sh and the Board matches ~/scratch/spacevibe-reins/tokens-d-board.html in the built app, recording each task's evidence under it; stop and ask if T1 finds that sessions repeat messages across files in a way the per-file ledger cannot handle, before T7 reads real logs, and before any push, merge or release.
