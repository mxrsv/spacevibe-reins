# Reins: native SwiftUI app

Spec: [2026-11-02-reins.md](../specs/2026-11-02-reins.md) (requirements, platform, interface, acceptance criteria AC1 to AC6).
Supersedes: [the Electron plan](2026-11-02-reins-electron.md), which stays as history and as the reference for behavior, contracts and screenshots.
Status: planned, nothing implemented. Written 2026-11-02.

## Approach

Rebuild the engine in Swift as a library and put a SwiftUI app on top. The Node `core/` and its fixtures stay in the repository only as a reference oracle, and are deleted once the Swift core matches it.

```
Package.swift                 swift-tools 6.0, language mode v5, platforms .macOS(.v15) (pinned: see Toolchain)
Sources/ReinsCore/            library, Foundation only, no UI import
  Roots, ProcessAdapter, LogFiles, TailReader        shared plumbing (guard for real roots under test)
  OrderedJSON, TOMLReader, Frontmatter                file formats; JSON edits keep key order and indent
  Inventory, UsageScan, Journal, Mutate               Loadout engine
  Rules                                               Claude read/write + capability grid, Codex read
  Activity, SessionTitles, Pricing, StopSession       Activity engine
Sources/Reins/                executable: App/, Shell/ (sidebar, palette, toast, tokens), Components/, Loadout/, Rules/, Activity/
Tests/ReinsCoreTests/         swift-testing; Fixtures/home (synthetic tree) and Fixtures/golden (JSON from the Node core)
Resources/Info.plist, scripts/  build-app.sh, dev.sh, test.sh adapted from spacevibe-board
```

Toolchain facts taken from `spacevibe-board/AGENTS.md` (verified there, not yet here): Command Line Tools only, Swift 6.3.2; `platforms: [.macOS(.v15)]` and `LSMinimumSystemVersion` must agree or the binary refuses to launch; swift-testing needs `scripts/test.sh` because bare `swift test` runs nothing; Swift 5 language mode; a Developer ID signature keeps TCC grants across rebuilds.

Parity method: `scripts/fixture-home.mjs` (kept as a dev tool) builds the synthetic HOME; a Node script writes JSON goldens from the Node core for that tree; the Swift tests load the same tree and compare. Tests never need Node. Goldens and the tree are synthetic only (`AGENTS.md` R2).

## Decisions made in this plan (reversible)

- Two targets, `ReinsCore` and `Reins`, so tests and later tools use the engine without the UI.
- Order-preserving JSON editing is written by hand (`JSONSerialization` drops key order); unchanged files must round-trip byte for byte.
- Codex TOML is read with a small reader and never written (Rules decision A from the Electron plan stands: Claude writes, Codex displays).
- Old Codex logs are `.jsonl.zst`; Swift has no zstd in Foundation or Compression. Vendor a decompress-only zstd C target (BSD); a system library is acceptable only if spike S0.2 shows it also builds on Linux and Windows.
- Concurrency: scans and log reads run in actors off the main thread; the UI reads published snapshots. Nothing synchronous over logs runs on the main actor.
- No sandbox, hardened runtime, Developer ID signing, notarization at release. Folder consent prompts (Documents, Desktop) are handled: a denied folder reads as "not readable", never as empty.
- Windows and Linux are not built now but stay possible (spec, Platform). Rules that keep the door open: `ReinsCore` imports Foundation only (no AppKit, no Darwin-only API, no `FSEvents`; a file watcher goes behind a protocol); every OS call lives in `ProcessAdapter`; the zstd decoder is the vendored C target, not a system library; a `reins-cli` target prints the engine's snapshots as JSON; `Package.swift` pins only `.macOS(.v15)`. Stop (R6) relies on SIGTERM and `ps`/`lsof`, so a Windows adapter is a separate design, not a port.
- The Electron renderer in the working tree is not touched until the Swift app reaches parity; its screenshots under `~/scratch/spacevibe-reins/shots/` are the visual reference together with `b-matrix.html`.

## Tasks

Phase S0 and S1 first; S2 modules then run in parallel by owner; each UI phase ends with screenshots and the owner's eye approval before its commit (`CLAUDE.md` branching rule).

### Phase S0: spikes (evidence under each task)

- [x] S0.1 Toolchain: build and launch an empty SwiftUI window from `Package.swift` with CLT only, using the board's scripts; run one swift-testing test through `scripts/test.sh`; record `vtool -show-build-version`. Done 2026-11-02: Swift 6.3.2, `build-app.sh` builds in about 31 s, `vtool` reports minos 15.0, signed with the Developer ID identity (no prompt), one window of 960x632 seen and quit. `scripts/test.sh` runs 86 tests in 10 suites; bare `swift test` fails to compile here (`no such module 'Testing'`).
- [x] S0.2 zstd: decide system library vs vendored decoder; prove it reads a `.jsonl.zst` rollout fixture. Done 2026-11-02: no usable system zstd (SDK has no header, `/usr/lib` no libzstd, Compression has no zstd), so `CZstd` vendors decompress-only zstd v1.5.7 (checksum recorded in `Sources/CZstd/README.md`); byte-identical reads of Node-made and CLI-made files, two frames, and a 5.7 MB stream.
- [ ] S0.3 TCC: read a `<project>/.claude` folder under `~/Documents` from the signed app; record the prompt, the denied behavior and what survives a rebuild (signing identity per board rule B3).
- [ ] S0.4 Process facts: `Process` with `ps`, `lsof` and `kill` (same lock-fd mapping as the Electron plan 0.3 evidence), and the signal behavior of both CLIs for Stop (spec "To verify"; needs a live session, see Action needed).
- [ ] S0.5 Real-CLI check (AC2, owner): a skill, agent, hook and permission written by `ReinsCore` is honored by a real `claude` and `codex` on a throwaway config.

- [ ] S0.6 Portability: `swift build` of a stub `ReinsCore` (one JSON read, one `Process` call) on Linux, in a container or CI. Record whether `swift-testing` runs there and whether Swift on Windows builds the same stub. Unverified today; this is the cheapest signal that the door is open. Repeat on Linux whenever `ReinsCore` gains a dependency.

### Phase S1: scaffold and shared plumbing

- [x] S1.1 `Package.swift`, `Resources/Info.plist`, `scripts/{build-app,dev,test}.sh`, an empty window titled Reins. Commit. Done (commit `2ca820a`).
- [x] S1.2 `AGENTS.md` rewrite for the Swift app (D8): stack, commands, toolchain rules B1 to B4 as they apply here, boundary rules R1 to R4 (temp HOME, no real data in committed files, no secrets, never execute hooks or recorded commands), the no-network rule, the Node oracle and its removal. Remove lines about Electron only at cutover (S8). Done (commit `7fbfb84`, Swift section added to `AGENTS.md`; the Electron text stays until S8.3).
- [x] S1.3 `Roots` with the AC3 guard (when `REINS_TEST=1`, a root under the real home throws; unit tests), `OrderedJSON` (parse, edit, serialize, byte round trip), `TOMLReader`, `Frontmatter`, `LogFiles` (plain, `.jsonl.zst`), `TailReader`. Done: `Roots` guard, `OrderedJSON` (byte round trip on 11 styles, edits splice only the edited region), `TOMLReader`, `Frontmatter`, `LogFiles`, `TailReader`.
- [x] S1.4 Golden pipeline: commit `Tests/.../Fixtures/home` generated by `scripts/fixture-home.mjs`, and `Fixtures/golden/*.json` written by one Node script from `core/`; a Swift test that loads both. Done: `scripts/make-golden.mjs` is idempotent; extra sections go in `scripts/golden/<name>.mjs`; the fixture tree is materialized at the fixed path `/private/tmp/reins-fixture-home` because hook and project ids hash absolute paths.

### Phase S2: engine, in parallel (each module compares to its goldens)

- [ ] S2.1 Inventory: skills, agents, hooks of both CLIs, plugin ownership, dead hooks, project discovery (cwd from the newest logs plus Codex `[projects]`), the cell contract (`counted`, `pending`, `unmeasurable`, `missing`) and filter counts with dead hooks only under Dead.
- [ ] S2.2 UsageScan: streaming JSONL and zstd reader, per-hook runs and errors (the `attachment.blockingError.command` shape), skill and agent counts, cache with a scan version, windows, runs off the main thread.
- [ ] S2.3 Journal and Mutate: add, remove, copy between CLIs, undo with the same bytes, trash backups; install-from-source is out of the first cut.
- [ ] S2.4 Rules: Claude `permissions.allow|ask|deny` read, add, remove, change verdict, capability grid and its mapping table, preview and set capability, refuse on `mixed`, all journaled; Codex reader (keys, profiles, trust, rules counts) with the secrets canary test.
- [ ] S2.5 Activity: live sessions for both CLIs, failures grouped with `laterPass`, file history labels, titles and project names, pricing table (estimated cost), the UNMEASURABLE wording; `StopSession` after the S0.4 findings, with a confirmation contract (the UI asks, the engine only terminates a pid it re-validates).

### Phase S3: shell and shared views (UI gate)

- [ ] S3.1 Tokens (dark and light, `--claude`/`--codex` equivalents as `Color` constants and asset-free), `NavigationSplitView` sidebar with counts, top bar, hint bar, hidden-inset window.
- [ ] S3.2 `⌘K` palette, toast with Undo wired to the journal, shared views: grouped list and row, CLI tag, segmented control, filter chip, `UsageCell` with the five states and legend, empty state, banner.
- [ ] S3.3 Fixture-HOME launch for development (`scripts/dev.sh` with a synthetic home), screenshots to `~/scratch/spacevibe-reins/shots/`, owner eye approval.

### Phases S4 to S6: screens (UI gates, in parallel after S3)

- [ ] S4 Loadout: Matrix table, filter chips, scope select, Add to CLI, remove, plugin and project rows read-only, scan progress, error and empty states. Eye approval.
- [ ] S5 Rules: capability grid with confirm sheet, expandable concrete rules, scope selector, rule list with add, remove and change verdict, read-only Codex group and the unrestricted state. Eye approval.
- [ ] S6 Activity: lanes per CLI, sessions, failures, file history, unmeasurable reasons on hover, Stop with confirmation, honest loading state while the first wide read runs. Eye approval.

### Phase S6T: Tokens tab (added to the spec 2026-11-03, after S2 and S3)

- [ ] S6T.1 Direction: the owner picks one layout from the click-through mocks in `~/scratch/spacevibe-reins/` (`tokens-*.html`) and the spec records it. No UI code before this.
- [ ] S6T.2 `TokenLedger` in `ReinsCore`: fold token usage per hour, CLI, model and project using the same deduplication as Activity; normalize Codex input; persist the rollup under the app's data folder with mode 0600 and merge on rescan so a vanished log keeps its past days (unlike the usage cache, which drops entries for missing files, see `core/usage.mjs` `scan`). Tests against `TempHome`, including AC8.
- [ ] S6T.5 Price table: add the logged models that have none today (`gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.5`, `claude-opus-5`, `claude-fable-5-1`, `claude-haiku-5-5` and the rest of the 4.21B of 24.57B tokens measured 2026-11-03) to `Pricing.swift` and `core/pricing.json` together, because a test compares them, each with its source and `fetchedAt`. A model that needs tier information stays unpriced on purpose. TokenTracker prices these names, so without this the estimate undercounts next to it.
- [ ] S6T.3 Screen for the picked direction with loading, empty and unpriced-model states. Screenshots to `~/scratch/spacevibe-reins/shots/`.
- [ ] S6T.4 AC7: compare with TokenTracker's `~/.tokentracker/tracker/queue.jsonl` on the owner's Mac, per local day, CLI and field; record the differences and causes here. Read-only, and the comparison output stays out of git.

### Phase S7: package

- [ ] S7.1 `build-app.sh`: release build, bundle, Developer ID signature, hardened runtime, verification output; notarization is release work.
- [ ] S7.2 UI tests are not available without Xcode; cover flows with `ReinsCore` tests plus a scripted launch against the fixture HOME and screenshots.

### Phase S8: accept and cut over

- [ ] S8.1 AC5: run the packaged app with the network off and open all four tabs.
- [ ] S8.2 AC1: the owner times the permission task (find, remove, undo) under one minute.
- [ ] S8.3 Parity reached: delete `core/`, `electron/`, the Electron renderer, `e2e/`, the Node build files and the Electron lines in `AGENTS.md` and `README.md`/`CHANGELOG.md` where they exist (D8, D12), after the owner agrees. Mark this plan historical (D1).

## Acceptance map

| AC | Covered by |
| --- | --- |
| AC1 find, remove, undo a permission in a minute | S5, S8.2 |
| AC2 a real CLI honors what the app writes | S0.5, S2.3, S2.4 |
| AC3 tests never touch the real config | S1.3 guard, every `ReinsCore` test |
| AC4 a running session of each CLI, limits stated | S2.5, S6 |
| AC5 offline | S8.1 |
| AC6 owner approves the UI by eye | S3.3, S4, S5, S6, S6T.3 |
| AC7 Tokens matches TokenTracker | S6T.4 |
| AC8 history survives a deleted log | S6T.2 |

## Action needed from the owner

- S0.5 and the signal checks of S0.4: run a real `claude` and `codex` session (needs your logins).
- Eye approval at S3.3, S4, S5, S6, S6T.3, the direction pick at S6T.1 and the AC1 timing at S8.2.
- Tell any other session still working in this repository that the platform changed; commits to `main` on Electron after this point are reference only.

## Handoff

- Checkout: `main`. The Electron renderer and its IPC are uncommitted in the working tree and belong to the superseded plan; do not delete them before S8.3.
- Known facts carried over: Codex permission schema, live-state findings, hook error root cause, Rules mapping table and capability semantics are in the Electron plan's task evidence; `core/` is the behavior reference including `stopSession` and compressed Codex logs.
- Remaining: everything above.

`/goal` Deliver the native SwiftUI Reins per docs/specs/2026-11-02-reins.md: complete docs/plans/2026-11-02-reins-swiftui.md phases S0 to S8 so that AC1 to AC8 hold, with the Swift core matching the Node goldens, tests running only against temp HOME, every UI phase approved by the owner by eye and each task's evidence recorded under it; stop and ask at owner-only steps, at deletion of the Node and Electron code, and before any push, merge or release.
