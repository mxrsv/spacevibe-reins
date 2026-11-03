# Reins: native SwiftUI app

Spec: [2026-11-02-reins.md](../specs/2026-11-02-reins.md) (requirements, platform, interface, acceptance criteria AC1 to AC6).
Supersedes: [the Electron plan](2026-11-02-reins-electron.md), which stays as history and as the reference for behavior, contracts and screenshots.
Status: in progress; implementation and outstanding acceptance gates are recorded below. Started 2026-11-02.

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

- [ ] S0.6 Portability: `swift build` of a stub `ReinsCore` (one JSON read, one `Process` call) on Linux, in a container or CI. Record whether `swift-testing` runs there and whether Swift on Windows builds the same stub. Unverified today; this is the cheapest signal that the door is open. Repeat on Linux whenever `ReinsCore` gains a dependency, and check that `Package.swift` still resolves there now that it declares Sparkle, a macOS-only binary package.

### Phase S1: scaffold and shared plumbing

- [x] S1.1 `Package.swift`, `Resources/Info.plist`, `scripts/{build-app,dev,test}.sh`, an empty window titled Reins. Commit. Done (commit `2ca820a`).
- [x] S1.2 `AGENTS.md` rewrite for the Swift app (D8): stack, commands, toolchain rules B1 to B4 as they apply here, boundary rules R1 to R4 (temp HOME, no real data in committed files, no secrets, never execute hooks or recorded commands), the no-network rule, the Node oracle and its removal. Remove lines about Electron only at cutover (S8). Done (commit `7fbfb84`, Swift section added to `AGENTS.md`; the Electron text stays until S8.3).
- [x] S1.3 `Roots` with the AC3 guard (when `REINS_TEST=1`, a root under the real home throws; unit tests), `OrderedJSON` (parse, edit, serialize, byte round trip), `TOMLReader`, `Frontmatter`, `LogFiles` (plain, `.jsonl.zst`), `TailReader`. Done: `Roots` guard, `OrderedJSON` (byte round trip on 11 styles, edits splice only the edited region), `TOMLReader`, `Frontmatter`, `LogFiles`, `TailReader`.
- [x] S1.4 Golden pipeline: commit `Tests/.../Fixtures/home` generated by `scripts/fixture-home.mjs`, and `Fixtures/golden/*.json` written by one Node script from `core/`; a Swift test that loads both. Done: `scripts/make-golden.mjs` is idempotent; extra sections go in `scripts/golden/<name>.mjs`; the fixture tree is materialized at the fixed path `/private/tmp/reins-fixture-home` because hook and project ids hash absolute paths.

### Phase S2: engine, in parallel (each module compares to its goldens)

- [x] S2.1 Inventory: skills, agents, hooks of both CLIs, plugin ownership, dead hooks, project discovery (cwd from the newest logs plus Codex `[projects]`), the cell contract (`counted`, `pending`, `unmeasurable`, `missing`) and filter counts with dead hooks only under Dead. Done 2026-11-02 (commits 6f1e80a); golden parity with the Node core where the module has one.
- [x] S2.2 UsageScan: streaming JSONL and zstd reader, per-hook runs and errors (the `attachment.blockingError.command` shape), skill and agent counts, cache with a scan version, windows, runs off the main thread. Done 2026-11-02 (commits 6f1e80a); golden parity with the Node core where the module has one.
- [x] S2.3 Journal and Mutate: add, remove, copy between CLIs, undo with the same bytes, trash backups; install-from-source is out of the first cut. Done 2026-11-02 (commits caf4038, 6d02eee, c659943); golden parity with the Node core where the module has one.
- [x] S2.4 Rules: Claude `permissions.allow|ask|deny` read, add, remove, change verdict, capability grid and its mapping table, preview and set capability, refuse on `mixed`, all journaled; Codex reader (keys, profiles, trust, rules counts) with the secrets canary test. Done 2026-11-02 (commits 67482db); golden parity with the Node core where the module has one.
- [x] S2.5 Activity: live sessions for both CLIs, failures grouped with `laterPass`, file history labels, titles and project names, pricing table (estimated cost), the UNMEASURABLE wording; `StopSession` after the S0.4 findings, with a confirmation contract (the UI asks, the engine only terminates a pid it re-validates). Done 2026-11-02 (commits db88567); golden parity with the Node core where the module has one.

### Phase S3: shell and shared views (UI gate)

- [x] S3.1 Tokens (dark and light, `--claude`/`--codex` equivalents as `Color` constants and asset-free), `NavigationSplitView` sidebar with counts, top bar, hint bar, hidden-inset window. Done 2026-11-02 (commits 97307dc); golden parity with the Node core where the module has one.
- [x] S3.2 `⌘K` palette, toast with Undo wired to the journal, shared views: grouped list and row, CLI tag, segmented control, filter chip, `UsageCell` with the five states and legend, empty state, banner. Done 2026-11-02 (commits 97307dc); golden parity with the Node core where the module has one.
- [ ] S3.3 Fixture-HOME launch for development (`scripts/dev.sh` with a synthetic home), screenshots to `~/scratch/spacevibe-reins/shots/`, owner eye approval. Built (Activity commit bc3819e; `scripts/dev-fixture.sh`); owner eye approval pending.

### Phases S4 to S6: screens (UI gates, in parallel after S3)

- [ ] S4 Loadout: Matrix table, filter chips, scope select, Add to CLI, remove, plugin and project rows read-only, scan progress, error and empty states. Eye approval. Built (commit 4a968ee); owner eye approval pending.
- [ ] S5 Rules: capability grid with confirm sheet, expandable concrete rules, scope selector, rule list with add, remove and change verdict, read-only Codex group and the unrestricted state. Eye approval. Built (commit 694e39a); owner eye approval pending.
- [ ] S6 Activity: lanes per CLI, sessions, failures, file history, unmeasurable reasons on hover, Stop with confirmation, honest loading state while the first wide read runs. Eye approval. Built (commit bc3819e); owner eye approval pending, Stop never run against a live process.

### Phase S6T: Tokens tab

Own plan: [2026-11-03-reins-tokens.md](2026-11-03-reins-tokens.md), after S2 and S3.

### Phase S7: package

- [ ] S7.1 `build-app.sh`: release build, bundle, Developer ID signature, hardened runtime, verification output; notarization is release work.
- [ ] S7.2 UI tests are not available without Xcode; cover flows with `ReinsCore` tests plus a scripted launch against the fixture HOME and screenshots.
- [ ] S7.3 Updater (AC7): Sparkle 2.10.0 in the `Reins` target, `UpdateController`, "Check for Updates…" menu item, toast on a scheduled find, `build-app.sh` embeds and signs the framework and takes `REINS_UPDATE_FEED_URL`, `scripts/test-update.sh`, `scripts/generate-update-feed.sh`. Built 2026-11-03; stays open until the owner approves the toast and update window by eye with AC6. Not in this task: notarization, the public feed host, a real release.
  - Window path, by hand: a Developer ID build with an `http://127.0.0.1` feed checked at launch with no prompt and opened Sparkle's window. Two mouse clicks on that window, not sent by the agent, started the download and the relaunch; build 2 then ran from the same path and its bundle verified. A relaunch does not inherit the launch environment, so that process read the real home (read-only until a write is clicked) and was stopped.
  - Toast path, by hand: with the last check set to 24 h minus 70 s, the check fired mid-session and logged `by user: false, toast: true` with no attention event. A launch in the foreground logged `toast: false` because Sparkle's window takes focus at once. The toast's look is in `~/scratch/spacevibe-reins/shots/update-toast/`; clicking View is unverified.
  - `scripts/test-update.sh`: wrong signature downloaded and still build 1 after quit, right signature build 2 and verifying. The two runs differ only in the signature.
  - No feed: an ad-hoc build logged `Updater off`, ran, and held no TCP socket.
  - Feed unreachable (AC5): a scheduled check at launch with no server logged `Could not connect to the server` and left only the main window on screen, no alert.
  - `scripts/generate-update-feed.sh`: refuses no DMG, an http prefix, a prefix with no trailing slash and an unstapled DMG. With `stapler` stubbed it wrote a signed HTTPS entry; a really stapled DMG is unverified.
  - Before the first release: repeat with an installed, quarantined, notarized older build. These local bundles were not quarantined, so Gatekeeper was not exercised (`spctl` rejects them as `Unnotarized Developer ID`).

### Phase S8: accept and cut over

- [ ] S8.1 AC5: run the packaged app with the network off and open all four tabs.
- [ ] S8.2 AC1: the owner times the permission task (find, remove, undo) under one minute.
- [ ] S8.3 Parity reached: delete `core/`, `electron/`, the Electron renderer, `e2e/`, the Node build files and the Electron lines in `AGENTS.md` and `README.md`/`CHANGELOG.md` where they exist (D8, D12), after the owner agrees. Mark this plan historical (D1).

## Progress log (2026-11-03)

Built by parallel subagents; the orchestrator re-ran `scripts/test.sh` (267 tests, 28 suites, pass) and `swift build` after the last change. Figures not marked otherwise are the agents' reports.

- Review (`review-change`, run `aeze29`, range `d366edc..694e39a`): correctness, tests and security-code all ran. Fixed in `887bc9c`, `a7a02d1`, `58fbb31`, `3d632fb`: fixtures hidden by a global gitignore; concurrent writes losing journal entries and edits (one process-wide recursive lock, unique temp names, a byte re-check before rename); project-scope symlink escape; symlinked Claude root; denied paths read as missing; unbounded TOML recursion; zstd memory (ring buffer, 512 MiB cap) and an exact-128-KB truncation bug; Rules confirmation bound to its scope; Loadout row, toast and double-click findings; test gaps for the pid guard, rollbacks and hook timeouts.
- Debt accepted (optimize or harden later): trash backups of edited settings are never pruned and may hold `env` secrets; Undo trusts paths in `journal.json`; Stop takes a Claude pid from a writable status file (needs the confirmation click; the pid is re-checked by start time only); the fixture tree lives at the fixed path `/private/tmp/reins-fixture-home`; the write lock covers this process only (another process is caught by the byte re-check, with a small window before `rename`); failed-command text shown in Activity is not redacted (same as the Node core; owner decision pending); no `NavigationSplitView`, so the sidebar cannot collapse; palette has no real combobox role.
- Not verified: hover, focus ring, keyboard flow, VoiceOver, window drag, the real `Menu` and `TextField` in a live window, polling, Stop against a live process, TCC prompts (S0.3), Linux build (S0.6), `scripts/build-app.sh` after the Sparkle change (another session owns it), a clean-checkout test run after `887bc9c`.

## Security remediation (2026-11-03)

The owner authorized fixes for the four reproduced security-review findings. These changes enforce the existing
[spec's config undoability, local-input safety and session Stop scope](../specs/2026-11-02-reins.md); they do not close
the remaining UI, real-CLI, portability or release gates.

- Config mutations preflight the journal while holding the write lock. If journal persistence fails after a mutation,
  completed operations are reversed; an unsuccessful rollback is reported explicitly instead of claiming no change.
  Hook rollback uses exact backups, including one shared backup for a dead-hook batch. User-initiated Undo keeps its
  existing behavior. Regression coverage: [MutationTransactionTests](../../Tests/ReinsCoreTests/MutationTransactionTests.swift).
- Threadless Codex session IDs bind the PID to the observed process start time. Stop refuses a stale identity, an old
  bare PID ID, or an unknown start. The Node golden comparison projects the opaque ID to its old display form only;
  [ActivitySafetyTests](../../Tests/ReinsCoreTests/ActivitySafetyTests.swift) separately tests read-to-Stop authorization.
- Status timestamps are bounded to supported ISO years before integer conversion or age arithmetic. Malformed values
  yield an unknown date/age; valid timestamps keep their existing output.
- Inventory file reads open nonblocking and check the opened descriptor with `fstat`. FIFOs and other nonregular files
  are refused; symlinks to regular files and byte limits remain supported. Regression coverage:
  [ReadHardeningTests](../../Tests/ReinsCoreTests/ReadHardeningTests.swift), with a rescue writer so a FIFO regression fails
  assertions rather than hanging the test run.
- Verification: `scripts/test.sh` passed 317 tests in 36 suites on the shared `main` checkout. An isolated copy of HEAD
  plus only this task's patch passed 281 tests in 31 suites, proving the commit does not require the other session's
  uncommitted refactors. Removing only `O_NONBLOCK` in that scratch copy made the two FIFO regression tests fail with
  five assertions; the exact production source was then restored.
- Independent correctness, tests and security-code reviews passed after strengthening the FIFO rescue assertion and
  the partial-rollback conflict case. Gitleaks found no secrets in the change; Semgrep had no Swift semantic coverage,
  so security-code approval relies on manual tracing and the regression tests.
- Delivery: one scoped commit on `main`, with unrelated staged and working-tree edits preserved; no push or PR. No real
  CLI configuration was edited; process-identity regressions use a fake adapter.
- Remaining limits of these fixes: process start identity has the precision of `ps lstart`; the OS check-to-signal race,
  crash recovery between config and journal persistence, and cross-process write races remain outside this change.

## Code-quality review and fixes (2026-11-03)

Three Fable 5.1 reviewers (architecture, clean code in `ReinsCore`, clean code in the app; run `dyo08c` at `de30381`) found
no blocker. The 11 medium findings were fixed by parallel Sonnet agents in two waves: commits `61b4dca`, `3d4a639`,
`dd87449`, `3021eba`, `35341a8`, `28b55b7` and `bdbd8d7`.

- One JavaScript-text helper set (`ActivityText`) and one SHA-1 (`Inventory.sha`) in `ReinsCore`; `readActivity` split into
  `liveProcesses`, `claudeSessions` and `codexSessions` (pure move); `ActivityCLI` and the app's `CLIKind` folded into
  `InventoryCLI`, colours in `Components/CLIStyle.swift`.
- `Journal` fails closed: a `journal.json` that exists but is not a JSON array makes `record` and `undo` throw 409 instead of
  being read as empty and overwritten. Deliberate break from the Node core; display reads stay lenient.
- One `ShotHarness` and one `ShotFit`; `REINS_SHOT_SCREEN=shell|loadout|rules|activity` is the only selector and CI loops all
  four. Before, the fixture variables selected Activity, so the Loadout and Rules shot assertions never ran in CI.
  `scripts/dev-fixture.sh --shots` without the variable now renders the demo shell, not Activity.
- `reinsFocusable` owns focus state and ring (Row and SegmentedControl keep theirs); `ScopePicker` shared by Loadout and
  Rules; `Metrics.fieldRadius/segmentRadius/kbdRadius/paletteRowHeight/paletteSectionHeight` and `ReinsFont.emptyStateIcon`;
  `TempHome.roots/strayTempFiles/mode` replace the per-suite copies, with the stricter `.tmp` filter everywhere.
- `Tests/ReinsTests` gained PaletteSearch, ShellModel, LoadoutRows, RulesScopes and ActivityFormat suites, then the
  Activity wording, scope option and Rules title/`scrubbed` tests the change review asked for.
- Change review (`review-change`, run `vfgila`, range `de30381..28b55b7`, six in-scope commits): correctness 0 blocker, 0
  high, 3 low still open (the journal refusal message says "not valid JSON" for `{}`, an unreadable file or a folder; an
  empty 0-byte `journal.json` now also blocks writes; the `--shots` default moved); tests 2 medium and 1 low closed by
  `bdbd8d7`; security-code 0 findings.
- Verification on the shared checkout: `scripts/test.sh` 360 tests in 39 suites pass; `swift build` clean; the four shot
  runs exit 0 (shell 16, loadout 20, rules 30, activity 10 PNGs; 62 `ok:` checks).
- Still open from the review (low): `ActivityText` is the module-wide text helper under an Activity name;
  `Sources/Reins/Tokens/` is the theme folder while the Tokens tab lands elsewhere; `Journal.history` and
  `Mutate.addSkill/addAgent` have no app caller; CI has no `tokens` shot case until the Tokens plan adds one.

## Acceptance map

| AC | Covered by |
| --- | --- |
| AC1 find, remove, undo a permission in a minute | S5, S8.2 |
| AC2 a real CLI honors what the app writes | S0.5, S2.3, S2.4 |
| AC3 tests never touch the real config | S1.3 guard, every `ReinsCore` test |
| AC4 a running session of each CLI, limits stated | S2.5, S6 |
| AC5 offline | S8.1 |
| AC6 owner approves the UI by eye | S3.3, S4, S5, S6, Tokens plan T8 |
| AC7 update found, installed and relaunched from a feed; wrong signature refused; no feed, no request | S7.3 |
| AC8 Tokens matches TokenTracker | Tokens plan T7 |
| AC9 history survives a deleted log | Tokens plan T2 |

## Action needed from the owner

- S0.5 and the signal checks of S0.4: run a real `claude` and `codex` session (needs your logins).
- Eye approval at S3.3, S4, S5, S6, the AC1 timing at S8.2.
- Tell any other session still working in this repository that the platform changed; commits to `main` on Electron after this point are reference only.

## Handoff

- Checkout: `main`. The Electron renderer and its IPC are uncommitted in the working tree and belong to the superseded plan; do not delete them before S8.3.
- Known facts carried over: Codex permission schema, live-state findings, hook error root cause, Rules mapping table and capability semantics are in the Electron plan's task evidence; `core/` is the behavior reference including `stopSession` and compressed Codex logs.
- Remaining: everything above.

`/goal` Deliver the native SwiftUI Reins per docs/specs/2026-11-02-reins.md: complete docs/plans/2026-11-02-reins-swiftui.md phases S0 to S8 so that AC1 to AC9 hold, with the Swift core matching the Node goldens, tests running only against temp HOME, every UI phase approved by the owner by eye and each task's evidence recorded under it; stop and ask at owner-only steps, at deletion of the Node and Electron code, and before any push, merge or release.
