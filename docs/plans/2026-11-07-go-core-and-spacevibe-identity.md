# Standalone Go core, stdio protocol and SpaceVibe identity

Record: Active task plan
Base revision: 39ff3f5 (main, clean at survey time)

## Requirements reference and delivery scope

- Decisions: [decision ledger](../specs/2026-11-07-core-port-and-spacevibe-identity-decisions.md) SV1 to SV17. Its "Open (not assumed)" items appear below as owner decisions D-1 to D-7. None of them is decided here.
- Product requirements and acceptance: [spec](../specs/2026-11-02-reins.md), acceptance criteria 1 to 5 (AC1 to AC5), plus AC6 (eye), AC7 (updater) and AC10 (Limits). Its Platform and Identity sections are superseded by SV1 to SV4 and SV9 to SV13. P0.1 rewrites them and adds the W20 traceability table that the ledger says is still owed.
- In scope: a Go core in this repo (SV1, SV6); the stdio JSON-RPC protocol (SV3); a SwiftUI shell that reaches the core only through `CoreClient` (SV4); deleting the Node oracle and then the Swift engine (SV5); the rename (SV9, SV11 to SV13, SV15); the runtime acceptance checks S0.5, S0.4, S0.3, S8.1 and S8.2, run once on the Go core (SV7, SV8). Release, GitHub, DNS and deploy steps appear only as gates (SV14, SV16).
- Out of scope (ledger): the Windows and Linux shells, the visual design of the `spacevibe.dev` landing page, and any edit outside this repo. See "Out of this plan, hand off".

### What this plan takes over from [2026-11-02-reins-swiftui.md](2026-11-02-reins-swiftui.md)

| Old task | Fate here |
| --- | --- |
| S0.1, S0.2 | Kept as history. CZstd (S0.2) is deleted in S.8; `klauspost/compress` replaces it in Go. |
| S0.3 TCC | Superseded by A3: Go core, `dev.spacevibe.app` identity. |
| S0.4 process facts and Stop | Superseded by A2, plus G1.9 and G2.2 (ported tests). |
| S0.5 real-CLI check | Superseded by A1. |
| S0.6 Swift portability | Dropped (ReinsCore is deleted). Replaced by X1 (cross-compile and Linux CI) and X2 (Windows hardware). |
| S1, S2 (Swift engine) | Kept as history. The Swift engine is the port source. |
| S7.3 updater | Re-verified with the new key in R2 (AC7). |
| S8.1, S8.2 | Superseded by A4 and A5. |
| S8.3 Node deletion | Superseded by P0.3. `scripts/fixture-home.mjs` stays: `scripts/dev-fixture.sh:53` and CI shots use it, and it imports only Node built-ins. |

When this plan is stored, replace those lines in the old plan with a pointer here, so there is one checklist (D0).

Affected sibling plans: [Agents](2026-11-05-reins-agents.md) A1 to A6 and [Tokens](2026-11-03-reins-tokens.md) T1 to T4 add engine modules to `Sources/ReinsCore`. Under SV1 and SV4 they move to the Go core. D-5 decides when.

## Conflicts between the ledger and the repo (surfaced, not resolved)

- **C1. "Byte for byte" (SV5) is not what the oracle checks today.**
  - Goldens are Node `JSON.stringify(v, null, 2)` output (`scripts/make-golden.mjs:49`). Swift compares parsed JSON: `FixtureHome.firstDifference` ignores key order and compares numbers as `NSNumber` (`Tests/ReinsCoreTests/Support/FixtureHome.swift:113-136`).
  - Swift compares projections, not raw output: `RulesGoldenView` (`RulesGoldenTests.swift:73-226`) and the sorted views in `ActivityGoldenTests.swift:16-32`.
  - Rules writes are compared as parsed settings on purpose (`RulesGoldenTests.swift:7-8`).
  - Swift also departs from Node deliberately: Codex IDs bound to process start time are projected back to `pid:<pid>` (`ActivityGoldenTests.swift:18-23`), and `Journal` fails closed (`Journal.swift:88-89`).
  - A Go core that matched the Node goldens literally would undo those security fixes. Proposed definition (Q1): Go implements current Swift behavior. Each golden test builds the same named projection the Swift test builds. Both sides are serialized with one canonical writer (sorted keys, ES6 number text, 2-space indent, `$HOME` substituted in keys and values) and must be equal as bytes. The golden files themselves stay frozen (SHA256SUMS check, P0.4).
- **C2.** SV5 says a wrong golden is "fixed together with its Swift test". Swift tests are deleted at S.8; after that it should read "with its Go test" (Q8).
- **C3.** SV9 ("no Reins reference remains") cannot hold for the frozen fixtures.
  - Hook and project ids in `inventory.json` and `mutate.json` are hashes of absolute paths under `/private/tmp/reins-fixture-home` (B6, `FixtureHome.swift:12`). Renaming the root changes those hashes, and nothing can regenerate them once Node is gone.
  - Also affected: `/nonexistent-reins-marker/` (`golden/activity.json:740`, `activity-home/.claude/projects/-work-app-a/aaaaaa81-….jsonl:16`) and `.reins/activity-proc.json` (`manifest.json:219`).
  - The ledger already wants fixtures reported separately. Recommendation: keep them as named skipped sites (Q2). Alternative: re-root once, with Go, after Go has passed at the old root.
- **C4.** SV8 puts S0.5 first in the review order, but SV7 requires S0.5 to run on the Go core. The split used here: P1 is an early read-only review of ReinsCore in SV8 order; A1 to A5 are the runtime checks, run once on Go, in the same order.
- **C5.** The 2026-11-02 spec still describes a Swift engine, a `reins-cli` executable and `reins.spacevibe.dev` (Platform and Identity). The W20 table is owed before code (P0.1).
- **C6.** AGENTS.md B8 says "never regenerate" the Sparkle key. SV13 replaces the key on purpose (new bundle id, and SV11 drops updates for v0.1.0). B8 is rewritten in R2, not silently broken.
- **C7.** The ledger lists "Spike" under Open, but the brief treats it as verified. Its evidence (commands and output) is not in the repo, so this plan marks it "reported verified" (see Handoff).

## Approach

### Shape

One Go binary, `spacevibe`, is the engine. The SwiftUI app spawns it as a child with argv `["rpc"]` and talks JSON-RPC 2.0 over stdio (SV3). Other entry points:

- `spacevibe <command> --json` for debugging; reads only (PR.3);
- `spacevibe --version`;
- `spacevibe statusline …`, only if D-3 says so.

The app links no engine code at the end (SV4). The core is bundled at `Contents/Helpers/spacevibe`, not `Contents/MacOS`, because after the rename `SpaceVibe` (the app) and `spacevibe` (the core) would collide on the default case-insensitive APFS.

### Directory and module (proposed; owner confirms in D-7)

`~/.claude/templates/project-structure.md` has no Go/Swift layout, so the repo convention applies: one top-level directory per toolchain with its own manifest (`site/` today). Recommended: `core/`, created only after P0.3 deletes the Node `core/`, so the two never coexist. This keeps the ledger's word "core" for one thing (UX2). Cost: `git log -- core/` mixes Node history with Go. Alternative: `engine/`. The module path is `spacevibe.dev/core`, which does not depend on the GitHub repo name (D-1 is open).

```
core/                         (new) go.mod, go.sum
  cmd/spacevibe/              argv dispatch; contract tests run the built binary
  internal/identity/          Name "spacevibe", EnvPrefix "SPACEVIBE_", DataDir ".spacevibe", Version (ldflags): the one constant each (SV12)
  internal/config/            the only env reader, fail-closed (workspace E5)
  internal/coreerr/           status + safe message (ReinsError)
  internal/textjs/            ActivityText, OrderedMap
  internal/ojson/             JSONValue + JSONParser + OrderedJSON (one Swift cycle, so one package)
  internal/toml/              TOMLReader
  internal/logs/              ZstdStream, LogFiles, TailReader, LineSplitter
  internal/roots/             Roots, resolvedPath, real-home guard, refuseRealHomeUnderTest
  internal/fsx/               AtomicWrite, write lock (in-process + flock), modificationTime, managedDirectory
  internal/pricing/           table + pricing.json (go:embed)
  internal/proc/              ProcessAdapter, ps/lsof parsers, darwin adapter, fixture adapter
  internal/inventory/         Inventory* files + Frontmatter
  internal/usage/             UsageScan*
  internal/activity/          SessionTitles, ActivityFold, ActivityGroups, Activity + ActivityStop (one cycle)
  internal/mutate/            FileEdit, Journal, JournalTrash, Mutate, MutateHooks, MutateItems, MutateHookEdit, MutateText (one cycle)
  internal/rules/             Rules* (RulesParse and RulesTypes are one cycle)
  internal/limits/            Limits + LimitsClaudeCache + LimitsClaudeStatusline + LimitsCodexLogs (one cycle)
  internal/statusline/        install, undo, capture (D-3)
  internal/rpc/               framing, dispatcher, notifications, cancel
  internal/goldentest/        fixture materializer, canonical writer, diff, leak guard (test helpers)
  testdata/fixtures/          moved from Tests/ReinsCoreTests/Fixtures, frozen, SHA256SUMS
  testdata/rpc/               recorded request/response transcripts (the shared contract)
```

Go forbids import cycles, so each of the seven Swift cycles the graph survey found becomes one package. Two Swift dependencies are cut by moving a helper:

- `InventoryFileIO` depends on `TailReader.modificationTime` (`InventoryFileIO.swift:82`). That helper moves to `fsx`.
- The Limits read path needs only `StatuslineSetup.managedDirectory`. It moves to `fsx`, so `limits` does not import `mutate`.

### Go version and dependencies

- Go: the version `go version` reports in P0.5, pinned by the `go` and `toolchain` lines in go.mod. This plan does not know the number.
- `github.com/klauspost/compress/zstd`: reported verified by the spike on the three `.zst` fixtures.
- `pelletier/go-toml/v2`: not added by default. `TOMLReader` is forgiving: it never throws, skips and counts bad lines, keeps raw tokens and lets the last duplicate win (`TOMLReader.swift:77-80`). go-toml is a strict parser, and its errors quote file text (an S-R3 problem). G1.3 runs the deciding check.
- Everything else comes from the standard library. `crypto/sha1` and `crypto/sha256` replace the hand-written `Sha1` and `ContentHash`, which existed only because CryptoKit is Apple-only (`InventoryHash.swift:18`).
- `CGO_ENABLED=0` everywhere (spike).

### Port order (derived from the dependency graph; confirmed by the owner as D-2)

Order inside each layer is free. Each domain package closes its golden only when the whole golden group is ported:

| Golden | Needs |
| --- | --- |
| `inventory.json` | inventory, usage, attach |
| `rules.json` | rules, mutate, toml, ojson |
| `mutate.json` | the whole `mutate` package |

1. **Layer 0 to 1 leaves (G1):** textjs, ojson, toml, logs, hashes, roots, fsx, pricing, proc, plus the golden harness.
2. **G2.1** inventory + usage (`inventory.json`, `usage.json`), in parallel with **G2.2** activity (`activity.json`, `activity-proc.json`).
3. **G2.3** mutate (`mutate.json`) → **G2.4** rules (`rules.json`).
4. **G2.5** limits (no golden today: G0.1 creates one first) → **G2.6** statusline (D-3).

Modules with no golden today:

| Module | First test to create |
| --- | --- |
| Limits (4 files) | Swift-recorded `limits.json`, G0.1 |
| StatuslineSetup and capture | `scripts/test-statusline.sh` becomes the end-to-end oracle |
| ActivityStop, SystemProcessAdapter | Ported unit tests and parser vectors |
| JSONParser | Ported `OrderedJSONTests` vectors |

### Parity method (C1, Q1)

`goldentest` materializes `testdata/fixtures/home` at `/private/tmp/reins-fixture-home`. It uses the same staging + rename + stamp-digest protocol as `FixtureHome.swift:41-65`, so a Go test run and a Swift test run can share the tree safely.

Each golden test builds the named projection and compares canonical bytes. On failure it prints a unified diff; on success it logs the canonical sha256. The named projections:

| Projection | What it does |
| --- | --- |
| `home-token` | Root path → `$HOME`, in keys and values |
| `inventory-sorted` | `items` and `hooks` by id |
| `usage-cold-warm` | Encoded cold scan; warm scan must equal cold |
| `activity-oracle` | Sessions by `cli\|id`, failures by `cli\|kind\|key`, files by path, Codex `pid:<pid>:<start>` → `pid:<pid>`, stats `{logs, truncated}` |
| `rules-view` | `ruleObject`, `gridObject`, preview outcome, `{ok}\|{error:{status,message}}`, parsed `.json` files after each write excluding the data folder, Codex flag view |
| `mutate-tree` | Path → sha1 of text with the root replaced, trash listing, ≥37 scenarios |

Every golden test also asserts its case count, so an unloaded golden cannot pass with zero cases (as `MutateTests.swift:16-21` does today).

### Protocol (SV3, SV12; full text in PR.1)

- **Framing.** NDJSON: one JSON-RPC 2.0 object per line. Request lines are capped at 1 MiB, response lines at 64 MiB. Batches are refused with `-32600`.
- **Handshake.** `initialize` params: `{protocolVersion, client:{name, version}}`. Result: `{protocolVersion, core:{name, version}, identity:{envPrefix, dataDir}, methods:[…]}`. A version mismatch gets `-32001`. Any request before `initialize` gets `-32002`.
- **Errors.** The standard codes, plus `-32000` with `data:{status, message}`. `message` is the ReinsError-style sentence and never quotes file content (S-R3).
- **Notifications.** `usage/progress`, `activity/report` and `$/cancelRequest`.
- **Activity.** `activity.subscribe` returns a full report first. The core polls every 3 s (`ActivityModel.swift:14`) and pushes a full report only when it changed. A reconnect re-subscribes and gets a fresh snapshot (resync); there are no deltas.
- **Output discipline.**
  - One writer goroutine owns stdout. At start the core dups fd 1 for the protocol and points `os.Stdout` at stderr, so a stray print can never corrupt the stream.
  - Logs go to stderr and carry fixed reasons only.
- **Lifecycle.**
  - On stdin EOF: stop reading, cancel reads, let in-flight writes finish (at most 5 s), exit 0.
  - No listener and no network imports (S-R5).
- **One-shot mode.** `--json` covers reads only. Exposing writes there would add a second writer for no debugging gain (reversible).

### Swift migration (SV4, W17)

1. **S.1, the seam.** `CoreService` (a protocol) plus Codable DTOs in a new folder, `Sources/Reins/Core/`.
   - Screens move from ReinsCore types to DTOs, backed at first by `InProcessCore`, an adapter over ReinsCore. No behavior change.
   - After S.1 the only UI file that imports ReinsCore is `InProcessCore.swift`.
2. **S.2, the client.** `CoreClient` implements `CoreService` over RPC.
   - A per-screen switch, `SPACEVIBE_CORE_SCREENS`, is honored only in DEBUG builds and under `SPACEVIBE_TEST=1`, so release builds keep the old path until a screen cuts over.
3. **Cut-over order:**
   1. Activity: reads, plus Stop.
   2. Limits.
   3. Loadout reads.
   4. Loadout writes, with Undo moving to the core.
   5. Rules.
   - Reads come first, so no write is mixed between engines until the cross-process lock (X-lock) exists.
   - Each cut-over flips the default for that screen and deletes that screen's in-process path in the same commit.
   - The app is releasable at every step. A release still waits for A1 to A5 (SV7).
4. **No visual change.** Per-screen evidence is contract tests plus pixel-identical fixture shots of the old and new path, instead of a per-region eye gate. The one eye task is F1 (Q5).
5. **S.8.** Deletes ReinsCore, CZstd, ReinsCoreTests, `InProcessCore` and, per D-3, ReinsStatusline. Only after every Go golden and the coverage ledger pass, and no UI path imports ReinsCore.

### Rename (SV9, SV11 to SV13, W21)

Baseline at 39ff3f5: 1,520 matching lines in 275 tracked files (case-insensitive `reins`). Recount at execution.

| Step | When | What |
| --- | --- | --- |
| R1 | Early, one commit | Env names and data folder across Swift, scripts, CI and tests. No aliases: if `REINS_TEST` lived on beside `SPACEVIBE_TEST`, one engine's real-home guard would be off without anyone noticing (AC3). |
| R2 | After R1 | Bundle id, names, Sparkle key, AGENTS.md B3, B8, B9 |
| R3 | After S.8 | Swift type, target and file names. ReinsCore is not renamed; it is deleted. |
| R4 | After R3 | Scripts and CI |
| R5 | After R2 | Site and living docs |
| R6 | Last | The "changed N of M" report |

Each name is one constant per language. Go `internal/identity` is the source. Swift learns the core's name, version, env prefix and data folder from `initialize` and hard-codes only the helper's path inside the bundle. A Swift test asserts its env-prefix constant equals the core's.

### Swift-to-Go traps seen in the code

- **JSON.** `encoding/json` sorts map keys, HTML-escapes `<>&` unless told not to, always escapes U+2028 and U+2029, and its errors quote input text. Use it only inside the canonical test writer (for ES6 float text). Config files go through `ojson` (`OrderedJSON.swift:21-28`: byte round trip, splice edits, duplicate key last-wins, depth 256).
- **JS text semantics.** `ActivityText` uses the JS whitespace set (`ActivityText.swift:10-15`, which includes U+FEFF; Go's `unicode.IsSpace` also counts U+0085), UTF-16 lengths, slices and sort (:61-74), and drops a half surrogate pair (:61). Do not use `strings.TrimSpace` or `strings.Fields`.
- **Regex.**
  - `Rules.boundary` uses lookarounds (`RulesParse.swift:60`), which RE2 rejects. Go's ASCII `\b` gives the same result.
  - Go's `\s` lacks `\v`, so the explicit JS space class (:59) must be ported.
  - ICU's `$` also matches before a final newline; Go's does not.
  - Every `NSRegularExpression` gets vector tests (patterns found in 9 files, e.g. `ActivityFold.swift:128-142`).
- **Paths.**
  - `Roots.resolvedPath` resolves the deepest existing ancestor of a missing path (`Roots.swift:104-117`). `filepath.EvalSymlinks` fails on missing paths, so port the algorithm.
  - The real home must come from the password database (`Roots.swift:81-86`), never from `os.UserHomeDir` (H1).
  - Symlinked targets stay links (`FileEdit.swift:171-183`).
- **Atomic write.** `O_EXCL` temp file, `fchmod`, `fsync`, read-back validation, a byte re-check before rename, `unlink` on failure (`FileEditAtomicWrite.swift`; `FileEdit.swift:80-85`).
- **Locks.**
  - `WriteLock` is an `NSRecursiveLock` (`WriteLock.swift:13`), nested by `addHook` → `FileEdit` → `Journal`. Go's `sync.Mutex` is not re-entrant, so split each function into a locked entry and an unlocked body.
  - Cross-process safety today is only the re-check before rename (`WriteLock.swift:10-11`). Add `flock` on `<data>/write.lock` in both engines (X-lock).
- **Trash moves.** `FileManager.moveItem` copies across volumes (`JournalTrash.swift:58`); `os.Rename` returns EXDEV (H13).
- **Lines.** `bufio.Scanner` stops at 64 KB. The scanner allows 32 MiB lines (`UsageScanner.swift:10`). Keep the zstd 512 MiB cap.
- **Unicode.** Swift `String` `==`, `<` and `Dictionary` keys use canonical equivalence; Go compares bytes (H14). `FileEdit.swift:57` already compares bytes.
- **Shared formats.** The usage cache is designed to be readable by either engine (`UsageScanCache.swift:3`). The journal format is fixed (`Journal.swift:6-10`, newest first, 200 entries). Both must stay identical while the engines coexist.
- **Numbers.** `String(Double)` in Swift (`LimitsClaudeStatusline.swift:44`) and Go's float formatting differ. Bytes on disk differ; parsed values agree.

### Alternatives rejected

| Rejected | Reason |
| --- | --- |
| Literal Node byte order for goldens | Fragile, and key order is not part of the contract (Swift ignores it). Kept as the fallback for Q1. |
| LSP `Content-Length` framing | More parsing on both sides for no gain over NDJSON. |
| Generating Swift DTOs from a JSON Schema | Adds tooling. Shared transcripts in `core/testdata/rpc` plus the PR.1 doc keep the contract in one place. |
| Keeping pure helpers like `attachUsage` and `filterCounts` in Swift (`LoadoutRows.swift:44,161,168`) | Two copies of engine logic. They move behind RPC. |

## Owner decisions and gates

Six of the ledger's "Open" items map to D-1 and D-3 to D-7 (the spike item is C7). D-2 is the port order. Hub `/vote`, marketing and the workspace map belong to a workspace session.

| ID | Decision (ledger Open item) | Recommendation (not assumed) | Blocks |
| --- | --- | --- | --- |
| D-1 | Repo name | none; `mxrsv/spacevibe` vs `spacevibe-app` | R4 (`release.sh:30`), R5 (`site/components/landing/content.ts:9`), GH1, REL1 |
| D-2 | Go port module order | the order above; answered by approving this plan | G2 |
| D-3 | `ReinsStatusline` as a core subcommand | `spacevibe statusline install\|undo\|capture`. A reinstall unwraps an old `…/.reins/bin/reins-statusline --capture …` command, not double-wrapping it (`StatuslineSetup.swift:44` checks only its own prefix). | G2.6, S.8 |
| D-4 | May the core run `claude --version` and `codex --version` | no task here needs it; S-R4 lists only `ps`, `lsof`, signals and the D-3 capture | S-R4 wording in R5 |
| D-5 | Does new UI work pause until the review and first CLI exist | engine tasks of the Agents and Tokens plans move to Go after G1; UI-only work continues; R3 waits for a quiet `Sources/` | S.1, R3, sibling plans |
| D-6 | Windows tests on real hardware | yes | X2 |
| D-7 | Name of the Go directory and module path | `core/`, `spacevibe.dev/core` | P0.3 (where `pricing.json` goes), P0.5 |

Outward-facing gates. Each needs the owner's explicit approval when it runs; none is scripted:

| Gate | Step |
| --- | --- |
| GH1 | Rename the GitHub repo |
| REL1 | Notarized release and publish (tag, push, `gh release create`) |
| GH2 | Mark the v0.1.0 release description deprecated (SV14) |
| WEB1 | Vercel project and preview deploy for `site/` |
| WEB2 | Repoint `spacevibe.dev` |
| WEB3 | DNS check for `reins.spacevibe.dev` |

## Tasks

Commit rules for every task: run `git status --porcelain` before the first edit (W11). One conventional commit per task (`type(scope): …`, W5) with `git commit -- <paths>`. A `git mv` lists both the old and the new paths. Never `git add -A`.

Standard checks:

```
GO   = cd core && go vet ./... && SPACEVIBE_TEST=1 go test -count=1 ./...
       → every package `ok`, no `FAIL`
SW   = scripts/test.sh
       → `Test run with N tests in M suites passed`, N > 0; N recorded before and after; any change in N explained
XC   = cd core && for t in darwin/arm64 darwin/amd64 linux/amd64 linux/arm64 windows/amd64 windows/arm64; do
         CGO_ENABLED=0 GOOS=${t%/*} GOARCH=${t#*/} go build -o /dev/null ./cmd/spacevibe || echo "FAIL $t"; done
       → no FAIL line
DOCS = bash ~/.claude/scripts/docs-compliance.sh && bash ~/.claude/scripts/docs-anchors.sh
       → exit 0, no violation reported
```

### Phase P0: preconditions (sequential, one session)

- [ ] **P0.1 Spec rewrite and W20 traceability (gate before P0.3)**
  - Files: `docs/specs/2026-11-02-reins.md` (Platform, Identity, a new traceability section)
  - Depends on: none
  - Build: rewrite Platform as Go core + SwiftUI shell + stdio protocol, and Identity as SpaceVibe / `spacevibe.dev`. Add a table with one row per decision: SV1 to SV17, the quoted decision, a requirement ID, an acceptance check (this plan's tasks implement the checks). Show the table to the owner before code (W20). The ledger stays the source of decisions.
  - Verify: `grep -cE '^\| SV(1[0-7]\|[1-9]) ' docs/specs/2026-11-02-reins.md` → 17; the date the owner saw the table is recorded; DOCS. (SV1 to SV17)
- [ ] **P0.2 Owner decisions at plan approval**
  - Build: record the answers to D-2 and D-7 (needed now) and any of D-1 and D-3 to D-6 the owner gives, in the ledger (the decision source), not in the plan.
  - Verify: the ledger "Open" list shows which items closed and the owner's words.
- [ ] **P0.3 Delete the Node oracle (S8.3, SV5)**
  - Files:
    - `git mv core/pricing.json core/internal/pricing/pricing.json` (or `engine/…` per D-7).
    - Update the path at `Tests/ReinsCoreTests/ActivityPricingTests.swift:9`.
    - Delete `core/*.mjs` (15 files), `scripts/make-golden.mjs`, `scripts/golden/*.mjs` (4), `test.mjs`, `package.json`.
    - In `AGENTS.md`: delete the "Node core" section, the `make-golden` and `npm test` rows and the last sentence of S-R2's paragraph about Node; point the Known-traps link (`core/log-files.mjs`) at `Sources/ReinsCore/LogFiles.swift`, and R6 at `Sources/ReinsCore/ActivityStop.swift`.
    - Reword the Swift test comments that cite `make-golden` (`Support/Fixtures.swift:4`, `Support/FixtureHome.swift:3,11,100`, `RulesGoldenTests.swift:5,73`, `ActivityGoldenTests.swift:5`, `MutateTests.swift:41`, `RulesTests.swift:7`) to "frozen goldens (SV5), last generated at <sha>".
  - Depends on: P0.1, D-7
  - Build: first record `git log -1 --format=%H -- core/activity.mjs` in Handoff; that commit is the Node behavior reference. Keep `scripts/fixture-home.mjs`. SV5 approves the deletion; git history is the backup (W9).
  - Verify:
    - `git ls-files core scripts/golden scripts/make-golden.mjs test.mjs package.json` → only the moved `pricing.json`.
    - SW, with N unchanged.
    - `git grep -nE 'make-golden|core/[a-z-]+\.mjs' -- AGENTS.md Sources Tests scripts .github` → empty.
    - `node scripts/fixture-home.mjs "$(mktemp -d)"` → exit 0.
    - DOCS.
- [ ] **P0.4 Move the frozen fixtures (SV5, B6)**
  - Files: `git mv Tests/ReinsCoreTests/Fixtures core/testdata/fixtures`. Edit `Tests/ReinsCoreTests/Support/Fixtures.swift:6-8` (new path from `#filePath`) and `Package.swift:44` (drop `exclude: ["Fixtures"]`). New: `core/testdata/fixtures/SHA256SUMS` over `golden/*.json`, `manifest.json`, `zst/*`. `scripts/test.sh` gains `(cd core/testdata/fixtures && shasum -a 256 -c --quiet SHA256SUMS)` before the tests.
  - Depends on: P0.3
  - Build: bytes do not change. The 2026-11-03 review found fixtures hidden by a global gitignore, so check every moved path stays tracked.
  - Verify:
    - `git diff --cached -M --name-status` → only `R100` renames plus the three edited files and `SHA256SUMS`.
    - `git ls-files core/testdata/fixtures | wc -l` equals `git ls-files Tests/ReinsCoreTests/Fixtures | wc -l` taken before the move (record both; about 304 on disk).
    - `git status --porcelain --ignored core/testdata` → no `!!` lines.
    - SW, with N unchanged.
- [ ] **R1 Env and data-folder rename, one commit (SV12, AC3)**
  - Files:
    - Swift sources: `Sources/ReinsCore/Roots.swift:23,41,52-57`, `FileEdit.swift:187,191`, `FileEditAtomicWrite.swift:16` (temp prefix `.spacevibe-<pid>-<rand>.tmp`), `StatuslineSetup.swift:5`, `Sources/ReinsStatusline/main.swift:64`, `Sources/Reins/App/AppEnvironment.swift:46-47`, `App/UpdateController.swift:108`, `App/LaunchMode.swift:13,16`, `Gallery/ShotRenderer.swift:26,45`, `Limits/LimitsShots.swift`, `Rules/RulesShots.swift`.
    - Tests: `Tests/ReinsCoreTests/Support/TempHome.swift:20,28`, the env key in `Support/FixtureHome.swift:35`, and every `REINS_*` in the test files.
    - Scripts and CI: `scripts/{test,dev,dev-fixture,build-app,release,test-update,rules-shots,test-statusline}.sh`, `scripts/fixture-home.mjs:86,89,224,242,345`, `.github/workflows/swift.yml`.
    - New: one Swift constant for prefix and folder in `Sources/ReinsCore/ReinsCore.swift`. It is deleted with ReinsCore; after S.8 the app reads both from `initialize`.
  - Depends on: P0.3. Must land before G1.6.
  - Build: every `REINS_*` becomes `SPACEVIBE_*`, and `.reins` becomes `.spacevibe`, with no aliases. Unchanged: the fixture-tree internals (the canonical root, the `.reins` folder `FixtureHome.swift:89` creates, the fixture's `.reins/activity-proc.json`; see C3) and the bundle id (R2). SV15: no migration code.
  - Verify:
    - `git grep -nE 'REINS_[A-Z_]+' -- Sources Tests scripts .github site` → empty.
    - `git grep -n '\.reins' -- Sources scripts Tests` → only the `FixtureHome.swift` fixture line(s), named.
    - SW, with N unchanged, including `RootsTests` "real home throws".
    - `scripts/test-statusline.sh` → exit 0.
- [ ] **P0.5 Go module scaffold and bundling (SV1, SV6, SV12)**
  - Files:
    - New: `core/go.mod`, `core/cmd/spacevibe/main.go`, `core/internal/identity/identity.go`, `core/internal/config/config.go`.
    - Edits: `.gitignore` (Go build output), `scripts/test.sh` (runs GO, builds the core to `.build/spacevibe-core/spacevibe`, exports `SPACEVIBE_CORE_BINARY` for Swift tests), `scripts/build-app.sh` (see Build), `scripts/dev.sh` and `scripts/dev-fixture.sh` (same helper), `.github/workflows/swift.yml` (`actions/setup-go` with `go-version-file: core/go.mod`).
  - Depends on: D-7, P0.4
  - Build:
    - Record `go version`. `spacevibe --version` prints `spacevibe <version>`. No arguments → usage on stderr, exit 2.
    - `build-app.sh` builds with `CGO_ENABLED=0 GOARCH=$(go env GOHOSTARCH) go build -trimpath -ldflags "-X spacevibe.dev/core/internal/identity.Version=<CFBundleShortVersionString>"` into `Contents/Helpers/spacevibe`.
    - It signs the helper inside out with the same `SIGN_ARGS` (hardened runtime) before the app, and prints `vtool -show-build-version` for the helper too.
  - Verify:
    - GO.
    - XC.
    - `scripts/build-app.sh` → `minos 15.0` for the app; `codesign --verify --deep --strict` passes; `codesign -dv build/Reins.app/Contents/Helpers/spacevibe 2>&1 | grep -E 'flags=.*runtime'` matches.
    - `build/Reins.app/Contents/Helpers/spacevibe --version` → the plist version.
    - SW shows the Go `ok` lines and the Swift summary.

### Phase P1: SV8 core review (read-only; parallel with G1)

- [ ] **P1 Severity-ranked review of ReinsCore**
  - Files: read only: `Sources/ReinsCore/**`, `core/testdata/fixtures/golden/*`, the spec's ACs and Known defects, and the "Debt accepted" line of the 2026-11-02 plan.
  - Depends on: P0.4
  - Build: run fresh-context reviewers (`code-reviewer`, `security-reviewer`, `silent-failure-hunter`) in SV8 order:
    1. What S0.5 exercises: the skill, agent, hook and permission formats written by `MutateItems`, `MutateText`, `MutateHooks` and `RulesSettingsFile`, checked against the CLIs' docs (UP6).
    2. Write safety and Stop: `FileEdit`, `AtomicWrite`, `Journal` (undo, rollback, fail-closed), `Trash`, `WriteLock`, `ActivityStop`, `ProcessAdapter`.
    3. TCC: denied must read as "not readable" (`InventoryFileIO.presence`, `RulesStore`).
    4. S8.1 offline and the S8.2 AC1 path.
    5. Feature gaps against the spec.
    - Findings are CRITICAL / HIGH / MEDIUM / LOW, with file:line, each labelled confirmed or "Hypothesis — unverified" (W13). The report goes to chat (D4).
    - Each finding maps to a "fix during port" task in G2 (with a new test), an SV5 golden fix, or a spec question. The caller adds these as tasks `G-fix.n` here.
  - Verify: every finding has a target task ID or an explicit "won't fix" from the owner. (SV8)

### Phase PR: protocol (parallel with G1)

- [ ] **PR.1 Protocol and architecture docs**
  - Files (new): `docs/internals/core-protocol.md`, `docs/internals/overview.md` (D5 entry point: shell/core split, data flow, the trap list above)
  - Depends on: P0.5
  - Build: document framing, lifecycle (argv `["rpc"]`, `initialize`, mismatch refusal, EOF), the method table (name, params, result, errors, side effects, journal entry), notifications, error codes, the canonical golden writer rules, and the security boundaries (stdout carries the protocol only, no listener, no content in errors).
  - Verify: DOCS. The PR.2 test `TestDocMethodTable` checks that the doc's method names equal the registered methods. (SV3, SV12)
- [ ] **PR.2 `internal/rpc` and `spacevibe rpc` (SV3, S-R5)**
  - Files (new): `core/internal/rpc/*.go`, `core/cmd/spacevibe/contract_test.go`, `core/testdata/rpc/*.jsonl`
  - Depends on: P0.5, G1.6 (config)
  - Build: NDJSON with the caps, handshake, errors, `$/cancelRequest`, single writer, stdout guard, EOF drain, recovering panics into `-32603` with a fixed message. A `contracttest` build tag adds a debug method (stray print, slow call); it is never in the shipped binary.
  - Verify:
    - `go test -count=1 -run TestContract -v ./cmd/spacevibe` → `--- PASS` for each named case: `handshake_ok`, `version_mismatch_refused`, `request_before_initialize`, `unknown_method`, `parse_error_continues`, `oversized_line`, `batch_refused`, `cancel_request`, `concurrent_requests`, `stray_print_on_stderr`, `eof_exits_zero` (exit 0 within 6 s, no `*.spacevibe-*.tmp` left), `no_listener` (darwin: `lsof -nP -a -p <pid> -i` prints nothing).
    - `go list -deps ./cmd/spacevibe | grep -xE 'net\|net/http\|crypto/tls'` → empty.
- [ ] **PR.3 One-shot `--json` (SV3)**
  - Files: `core/cmd/spacevibe/` (new subcommands)
  - Depends on: PR.2 and each read method as it lands
  - Build: `spacevibe inventory|usage|activity|limits|rules --json` print the same result object as the RPC method. Exit codes: 0 success, 1 core error (message on stderr), 2 usage. No write commands.
  - Verify: contract case `one_shot_equals_rpc` (byte-equal result on the fixture home); `spacevibe activity --json | python3 -m json.tool >/dev/null` → exit 0 under the fixture env.

### Phase G1: leaf ports (each package is its own directory, so these can run in parallel)

Each task ports the named Swift unit tests as Go table tests with the same vectors and records Swift vs Go case counts in the coverage ledger below.

- [ ] **G1.1 `textjs`** ← `ActivityText.swift` (incl. `OrderedMap` :254). Tests: the `ActivityText` vectors from `ActivityTests` and `ActivitySafetyTests`, plus new vectors with astral characters, U+0085 and U+FEFF. Verify: GO. (SV5)
- [ ] **G1.2 `ojson`** ← `JSONValue.swift`, `JSONParser.swift`, `OrderedJSON.swift`. Tests: `OrderedJSONTests` (the 11-style byte round trip; edits splice only the edited region), depth 256, invalid UTF-8, and errors carrying no content (S-R3). Verify: GO.
- [ ] **G1.3 `toml`** ← `TOMLReader.swift`, ported by hand. Deciding check for the dependency: parse each `core/testdata/fixtures/rules-home/codex-*/.codex/config.toml` with go-toml/v2 in a scratch program. If any errors, go-toml stays out of go.mod. Tests: `TOMLReaderTests`, plus the recursion bound from `ReadHardeningTests`. Verify: GO; the scratch result recorded here.
- [ ] **G1.4 `logs`** ← `ZstdStream.swift` (klauspost decoder: concurrency 1, memory and window capped at 512 MiB), `LogFiles.swift`, `TailReader.swift`.
  - Tests: `ZstdStreamTests` (small, twice, `large` against `zst/large.meta.json` sha256 and line count, `cli-made`, truncated), `LogFilesTests`, `TailReaderTests`, the FIFO case of `ReadHardeningTests`.
  - Add the klauspost/compress licence notice to `Sources/Reins/App/Credits.swift` (BSD; binary redistribution). Read the licence file in the module cache first.
  - Verify: GO.
- [ ] **G1.5 Hashes** ← `InventoryHash.swift` (`Sha1`, `sha`, `hookHash`), `JournalSHA256.swift`, replaced by `crypto/sha1` and `crypto/sha256`. Tests: the `JournalTests.swift:9-19` vectors and the hook ids in `golden/inventory.json`. Verify: GO.
- [ ] **G1.6 `roots`, `config`, `coreerr`** ← `Roots.swift`, `ReinsError.swift`, `FileEdit.refuseRealHomeUnderTest`. Port the `resolvedPath` algorithm itself and read the real home from the password database (H1). Tests: `RootsTests`, the guard cases of `WriteGuardTests`. Verify: GO; plus a darwin `CGO_ENABLED=0` build of the guard test with `HOME` overridden still throws. (AC3)
- [ ] **G1.7 `fsx`** ← `FileEditAtomicWrite.swift`, `WriteLock.swift`, `modificationTime`, `managedDirectory`. Locked entry and unlocked body pairs, plus `flock` on `<data>/write.lock`. Tests: the atomic-write cases of `FileEditTests`, `WriteConcurrencyTests` (goroutines), and a new two-process test that runs the test binary twice against one data folder (no lost journal entry). Verify: GO.
- [ ] **G1.8 `pricing`** ← `Pricing.swift`, plus the embedded `pricing.json`. Keep the summation order (`Pricing.swift:60`). Tests: `ActivityPricingTests`, which checks the table equals the JSON. Verify: GO.
- [ ] **G1.9 `proc`** ← `ProcessAdapter.swift`, plus the fixture adapter moved from `Sources/Reins/Activity/FixtureProcessAdapter.swift`.
  - The darwin adapter runs `/bin/ps` and `/usr/sbin/lsof` with `TZ=UTC LC_ALL=C` and the 3 s / 5 s timeouts, uses `syscall.Kill`, and maps ESRCH and EPERM.
  - The fixture adapter works only under `SPACEVIBE_TEST=1`, with the same gating as `AppEnvironment.swift:46-57`.
  - On other OSes the adapter reports "not measurable on this OS".
  - Tests: `ProcessGuardTests`, plus vectors for `psLine` and `lockPath`.
  - Verify: GO; XC. (S-R4)
- [ ] **G1.10 `goldentest` harness**
  - Build:
    - The materializer (B6 path, stamp protocol).
    - The canonical writer.
    - The `home-token` normalizer (keys and values).
    - The unified diff.
    - The S-R2 leak guard: no real home path or user name anywhere under `core/testdata`, as `FixtureHomeTests` and `make-golden.mjs:66-72` did.
    - The SHA256SUMS freeze check.
  - Verify: `go test -count=1 -run 'TestFixture\|TestLeak\|TestFreeze' -v ./internal/goldentest` → PASS. In a scratch copy (F4), flip one golden byte and see `TestFreeze` fail, then discard the copy.

### Phase G0: goldens that must exist first

- [ ] **G0.1 Swift-recorded Limits golden (AC10)**
  - Files: new `Tests/ReinsCoreTests/LimitsGoldenTests.swift`; new `core/testdata/fixtures/golden/limits.json` and its line in SHA256SUMS
  - Depends on: P0.4
  - Build:
    - Every scenario of `LimitsTests` and the read side of `LimitsStatuslineTests`: Codex `token_count`, Claude cache, statusline snapshots incl. an account change and the highest-recent merge, a passed reset, a missing cache, an unknown shape, Gemini not measurable.
    - The output is `Limits.read` through the canonical writer, with record mode under `SPACEVIBE_RECORD_GOLDEN=1`.
    - The file is committed with the test that writes it (SV5).
  - Verify: SW passes in compare mode; a second record run leaves `git diff --stat` empty.

### Phase G2: domain ports (each registers its RPC methods and contract cases)

- [ ] **G2.1 `inventory` + `usage` (`inventory.json`, `usage.json`)**
  - Depends on: G1.2 to G1.6, G1.10
  - Build:
    - Methods: `inventory.read`, `usage.scan` (with `usage/progress`, cancellable), and `loadout.rows` (attach + filterCounts, which move out of `LoadoutRows.swift`).
    - The usage cache format stays identical to Swift's (`UsageScanCache.swift:3-16`).
  - Tests: `TestGoldenInventory` (`inventory-sorted`), `TestGoldenUsage` (`usage-cold-warm`), `InventoryTests` and `UsageScanTests` units, nonregular-file refusal, cancellation before the first file leaves no cache.
  - Verify: `go test -count=1 -run TestGolden -v ./internal/inventory ./internal/usage` → PASS, with the canonical sha256 logged; GO; contract cases `inventory_read` and `usage_scan_progress`. (SV5)
- [ ] **G2.2 `activity` (`activity.json`, `activity-proc.json`)**
  - Depends on: G1.1, G1.4, G1.8, G1.9, G1.10
  - Build: methods `activity.read`, `activity.subscribe`, `activity.unsubscribe`, `activity.stop`. Engine state lives in the core (incremental fold; resync = full read).
  - Tests:
    - `TestGoldenActivityShared` and `TestGoldenActivityExtra` (`activity-oracle`), still asserting the covered cases (`ActivityGoldenTests.swift:51-55,73-79`).
    - The compressed-rollout case: a second read folds nothing again; a tail cut is counted.
    - `ActivityStopTests`, `ActivitySafetyTests` (start-bound IDs refuse stale ones), the 8 `ActivityFold` regex vectors.
  - Verify: as G2.1, for `./internal/activity`; contract cases `activity_subscribe_snapshot`, `activity_notification_on_change`, `activity_resync_after_restart`, `stop_refuses_unknown`. (AC4)
- [ ] **G2.3 `mutate` (`mutate.json`)**
  - Depends on: G1.2, G1.5, G1.6, G1.7, G2.1
  - Build:
    - Methods: `loadout.copyToOther`, `loadout.removeItem`, `loadout.removeDeadHooks`, `journal.undo`, `journal.history`. `addSkill` and `addAgent` have no app caller and are not exposed.
    - The journal format and fail-closed behavior are identical to Swift's.
    - The trash move falls back to copy + fsync + remove on EXDEV, as `FileManager.moveItem` does (H13).
  - Tests: `TestGoldenMutate` (`mutate-tree`, ≥37 scenarios); `MutateTests` units; `JournalTests`; `MutationTransactionTests`; `FileEditTests`; `WriteGuardTests`; `WriteConcurrencyTests`; an injected-EXDEV test.
  - Verify: as G2.1; plus new `Tests/ReinsTests/CoreJournalInteropTests.swift`, run by SW against the built core: a Swift-recorded entry is undone by Go and a Go-recorded one by Swift, with byte-identical results.
- [ ] **G2.4 `rules` (`rules.json`)**
  - Depends on: G2.1 (`discoverProjects`), G2.3
  - Build: methods `rules.snapshot` (what `RulesSnapshot.swift:32-59` assembles), `rules.preview`, `rules.setCapability`, `rules.add`, `rules.remove`, `rules.changeVerdict`, `rules.check` (live validation for `RulesScopes.swift:70`). Regex per the trap list.
  - Tests: `TestGoldenRules` (`rules-view`): the shared and main reads, 5 Codex cases, more than 100 writes with more than 20 refusals and at least 1 no-op (`RulesGoldenTests.swift:42,56,69`). Plus the byte tests of `RulesTests`.
  - Verify: as G2.1. (AC1, AC2 preconditions)
- [ ] **G2.5 `limits` (AC10)**
  - Depends on: G0.1, G1.4, G1.6, G1.7, G2.1 (`InventoryFileIO`)
  - Build: method `limits.read`; makes no network request and reads no credentials (spec, Limits).
  - Tests: `TestGoldenLimits` against `limits.json`; the read cases of `LimitsTests` and `LimitsStatuslineTests`.
  - Verify: as G2.1.
- [ ] **G2.6 `statusline` (D-3)**
  - Depends on: D-3, G2.3, G2.5
  - Build, if D-3 picks the subcommand:
    - `spacevibe statusline install | undo <id> | capture <data> <claudeRoot> <original>`.
    - Capture runs `/bin/sh -c <original>` through `os/exec` in Claude's process group (no `Setpgid`), copies stdin to it, honours the 1 MiB cap and propagates the exit status as `main.swift:71-76` does.
    - Install unwraps an old Reins wrapper.
    - The RPC method list has no path to capture; the contract case `rpc_cannot_capture` asserts it.
  - Tests: `LimitsStatuslineTests`; `scripts/test-statusline.sh`, pointed at `core/…/spacevibe statusline`.
  - Verify: `scripts/test-statusline.sh` → exit 0; GO. (S-R4)

### Phase S: Swift shell (W17, SV4)

- [ ] **X-lock Cross-process write lock in Swift (before S.6)**
  - Files: `Sources/ReinsCore/WriteLock.swift` (flock `<data>/write.lock` at the outermost depth), new `Tests/ReinsTests/CoreWriteLockInteropTests.swift`
  - Depends on: G1.7
  - Verify: SW. Concurrent Swift and Go writers hammering one journal → entry count equals the total written, no lost edit.
- [ ] **S.1 `CoreService` seam and DTOs, no behavior change (one commit per screen)**
  - Files:
    - New in `Sources/Reins/Core/`: `CoreService.swift`, `CoreTypes*.swift`, `InProcessCore.swift`.
    - Edited: `Sources/Reins/App/AppEnvironment.swift` (`core: any CoreService`; `performWithUndo` takes DTO journal entries; an app-side error DTO replaces `ReinsError.message`).
    - The screen models and views of Components, Shell, Limits, Activity, Loadout and Rules: the 51 files that import ReinsCore today.
    - `Tests/ReinsTests/*` rebuilt on DTOs.
  - Depends on: D-5, PR.1 (DTO shapes)
  - Verify:
    - SW (`StyleBoundaryTests` and `IconPolicyTests` green; N explained).
    - `git grep -l 'import ReinsCore' -- Sources/Reins` → only `Sources/Reins/Core/InProcessCore.swift`.
    - Fixture shots for `shell`, `loadout`, `rules`, `activity` and `limits` (`SPACEVIBE_SHOT_SCREEN=<s> scripts/dev-fixture.sh --shots <dir>`) are pixel-identical to the pre-change set. The comparison script lives in the scratchpad; any differing pixel is explained.
- [ ] **S.2 `CoreClient` (child process)**
  - Files: new `Sources/Reins/Core/CoreClient.swift`, new `Tests/ReinsTests/CoreClientTests.swift`
  - Depends on: PR.2, S.1
  - Build:
    - Binary: `Contents/Helpers/spacevibe`. The override `SPACEVIBE_CORE_BINARY` is honored only in DEBUG builds or under `SPACEVIBE_TEST=1`.
    - Spawn with argv `["rpc"]`, inheriting the environment.
    - `initialize` with the Swift protocol-version constant. The app takes name, version and identity from the result. A mismatch shows a fixed startup-problem text.
    - Restart with backoff; pending requests fail with a fixed "core restarted" error; writes are never retried automatically.
    - Re-subscribe Activity after a restart.
    - stderr goes to `os.Logger` at debug level.
    - Lines are read off the main actor.
  - Verify: SW includes `CoreClientTests`, all passing: handshake against the real binary on the fixture home; a `kill -9` of the core, after which the next call succeeds after re-init; every `core/testdata/rpc/*.jsonl` response decodes into its DTO; the Swift env-prefix constant equals the `initialize` value. (SV3, SV4, SV12)
- [ ] **S.3 Cut over Activity and Stop.** Depends on: G2.2, S.2. Build: make the core path the default; delete the in-process Activity path and `Sources/Reins/Activity/FixtureProcessAdapter.swift`. Verify: SW; ACT contract cases; identical `activity` shots; `git grep -nE 'readActivity|stopSession|SystemProcessAdapter|FixtureProcessAdapter' -- Sources/Reins` → empty. (AC4)
- [ ] **S.4 Cut over Limits** (sidebar block on every tab, and the page). Depends on: G2.5, S.2. Verify: SW; identical `limits` shots for both fixture variants (`typical`, `edge`); `git grep -n 'Limits.read' -- Sources/Reins` → empty. (AC10)
- [ ] **S.5 Cut over Loadout reads.** Depends on: G2.1, S.2. Verify: SW; identical `loadout` shots; `git grep -nE 'Inventory\.(read\|attachUsage\|filterCounts)\|UsageScanner' -- Sources/Reins` → empty.
- [ ] **S.6 Cut over Loadout writes, with Undo moving to the core.** Depends on: G2.3, X-lock, S.5. Verify: SW; `CoreJournalInteropTests`; contract write cases; `git grep -nE 'Mutate\.\|Journal\.undo' -- Sources/Reins` → empty.
- [ ] **S.7 Cut over Rules.** Depends on: G2.4, S.6. Verify: SW; identical `rules` shots incl. `SPACEVIBE_FIXTURE_CODEX` variants (`scripts/rules-shots.sh`); `git grep -nE 'RulesStore\|CodexPermissions\|Rules\.' -- Sources/Reins` → empty.
- [ ] **S.8 Delete the Swift engine**
  - Gate, all four required:
    - (a) every Go golden passes;
    - (b) the coverage ledger has no unmapped Swift test;
    - (c) `git grep -l 'import ReinsCore' -- Sources/Reins Tests/ReinsTests` lists only `InProcessCore.swift`;
    - (d) D-3 is answered.
  - Files: delete `Sources/ReinsCore`, `Sources/CZstd`, `Tests/ReinsCoreTests`, `Sources/Reins/Core/InProcessCore.swift` and, per D-3, `Sources/ReinsStatusline`. Edit `Package.swift` (targets, Sparkle comment) and `scripts/build-app.sh:56,104` (the statusline copy and sign). Delete `AGENTS.md` B5 and B7 (replaced in R5).
  - Verify:
    - `swift build` succeeds.
    - SW: N drops by exactly the deleted `ReinsCoreTests` count (record it).
    - GO.
    - `scripts/build-app.sh`.
    - Identical shots on all screens.
    - `git grep -n 'ReinsCore\|CZstd' -- Sources Tests Package.swift scripts .github` → empty. (SV4, SV5)

### Phase R: rename (W21)

- [ ] **R2 Bundle identity and the new Sparkle key (SV11, SV13)**
  - Files: `Resources/Info.plist:12-15,19,37-41,44-48`, `Sources/Reins/App/UpdateController.swift:44`, `Sources/Reins/Tokens/AppearanceStore.swift:43-44`, `scripts/generate-update-feed.sh:18`, `scripts/test-update.sh:9,17`, `scripts/dev.sh:28`; `AGENTS.md` B3, B8, B9 rewritten
  - Depends on: R1. Owner action: `generate_keys --account dev.spacevibe.app` (prints `SUPublicEDKey`), then a backup with `-x` into the password manager (it writes the owner's Keychain, W9).
  - Build: `CFBundleIdentifier` `dev.spacevibe.app`, `CFBundleName` SpaceVibe, the usage descriptions, the new `SUPublicEDKey`.
  - H7 check, local only: a build carrying the old public key against a `127.0.0.1` feed signed with the new key, and against a 404 feed. Record exactly what Sparkle shows in a scheduled and a manual check; the result feeds the REL1 decision on the new feed's asset name.
  - Verify:
    - `scripts/test-update.sh` → the wrong signature is refused and the right one installs and relaunches (AC7).
    - `/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/*.app/Contents/Info.plist` → `dev.spacevibe.app`.
    - DOCS.
- [ ] **R3 Swift target, type and file names**
  - Files:
    - Folders: `Sources/Reins` → `Sources/SpaceVibe`; `Tests/ReinsTests` → `Tests/SpaceVibeTests`.
    - Types: `ReinsApp`, `ReinsRootStyle`/`reinsRoot`, `ReinsType`/`.reinsText`, `ReinsIcon`, `ReinsGlyph` (and the output names in `scripts/generate-icons.mjs:19,332`), `ReinsButtonStyle`/`ReinsButtonKind`/`.reins(_:)`, `reinsFocusable`, `ReinsMark`, `ReinsSwitch`, `ReinsScrollView`, `ReinsTab`.
    - Text: window title and About (`ReinsApp.swift:15,33`); the string at `StyleBoundaryTests.swift:95`.
    - Names: `Package.swift` name and targets; `CFBundleExecutable` SpaceVibe; `build-app.sh:29-30`; `dev.sh:8,10`; `dev-fixture.sh:40`; `test-update.sh:22,49-58`; `release.sh:31`; the identifiers in `docs/DESIGN-LANGUAGE.md`.
  - Depends on: S.8, D-5, and no other session with uncommitted `Sources/` edits (W11)
  - Verify:
    - `swift build`; SW with N unchanged.
    - Rerunning `node scripts/generate-icons.mjs <icons.json>` gives no diff.
    - Shots identical except for renamed text; each difference listed.
    - `git grep -n -i reins -- Sources Tests Package.swift` → empty.
- [ ] **R4 Scripts and CI.** Files: the temp prefixes (`build-app.sh:74`, `release.sh:50`, `test-update.sh:24`, `dev-fixture.sh:37,44`, `.github/workflows/swift.yml:35`); `release.sh:30` `GITHUB_REPO` per D-1. Depends on: R3, D-1. Verify: `bash -n` on every script; `scripts/build-app.sh`; `scripts/release.sh --prepare` on a clean `main` (local; publishes nothing) → `SpaceVibe-<v>.dmg`; `git grep -n -i reins -- scripts .github` → empty.
- [ ] **R5 Site and living docs (SV9, SV10, SV16)**
  - Files:
    - `site/`: `site/**` (all 16 matching files from the inventory: `content.ts:9,13-15,45,255-265`, `reins-mark.tsx` → `spacevibe-mark.tsx`, `scroll-reveal.tsx:5`, `shots.ts:20`, the `directions/*` titles, `public/icon.svg:1`, `next.config.ts:5`, `README.md`, `AGENTS.md`).
    - New: `site/vercel.json` with the redirects. `output: "export"` (`site/next.config.ts:9`) rules out `next.config` redirects. The `/live` family → 308 to `https://active.spacevibe.dev/:slug*`, as the Hub does (`spacevibe-hub/next.config.ts:7-17`). Old Hub routes → same path on `kyant.dev`, as an explicit list read from `spacevibe-hub/app/**` (X2, read only); `/` and the landing's own paths are excluded and any conflict is listed for the owner.
    - New: `site/tests/redirects.test.mjs`.
    - Docs: `AGENTS.md` (full pass: B1 adds the helper's minos, B2, B6, S-R1 to S-R5, R6, Known traps, the "Public site" paragraph and the command table); `PRODUCT.md`; `docs/DESIGN-LANGUAGE.md`; `docs/internals/*`.
    - Draft release notes in the scratchpad: no migration, copy `~/.reins` by hand (SV15).
    - The idiom "take the reins" is replaced as well (reversible).
  - Depends on: R2, D-1, D-4
  - Verify: `cd site && npm run build` → exit 0; `grep -ri reins site/out | wc -l` → 0; `node --test site/tests/redirects.test.mjs` → pass; DOCS.
- [ ] **R6 Rename report (W21)**
  - Build: run `git grep -i -c reins` and report "changed N of M" against the 1,520-line baseline. Name each skipped site:
    - the fixtures (C3);
    - historical specs and plans (D1 history; file names keep their D4 paths);
    - `mocks/` (deleted at Tokens T8 and Agents A12);
    - false positives;
    - the v0.1.0 release text, reported separately (GH2).
  - Verify: the report is pasted in the Verification evidence section; every remaining hit belongs to a named category.

### Phase A: runtime acceptance on the Go core (SV7; SV8 order; final identity build)

Setup for every A task (S-R1):

```
T=$(mktemp -d /tmp/spacevibe-acc.XXXXXX)
export HOME=$T CLAUDE_CONFIG_DIR=$T/.claude CODEX_HOME=$T/.codex SPACEVIBE_HOME=$T/.spacevibe
open -n --env HOME=$T --env CLAUDE_CONFIG_DIR=$T/.claude --env CODEX_HOME=$T/.codex --env SPACEVIBE_HOME=$T/.spacevibe build/SpaceVibe.app
```

The owner signs both CLIs in to that home; real sessions spend quota. H9: Claude's credentials may live in the Keychain.

- [ ] **A1 S0.5, the real CLIs honor what the app writes (AC2)**
  - Build:
    - Seed `$T/.claude/skills/acc-probe/SKILL.md` (it tells the model to answer `ACC-SKILL-7f3`), `$T/.claude/agents/acc-agent.md` (`ACC-AGENT-91c`), and a Claude `SessionStart` hook that runs `touch $T/hook-claude`.
    - In the app: copy the skill, agent and hook to Codex; add the Claude rule `deny Bash(touch:*)` in Rules.
    - Run `claude -p` and `codex exec` prompts that invoke the skill and the agent, start a session, and ask for `touch $T/denied`.
    - Undo each write and compare sha256 of the files before and after.
    - Codex permissions are read-only until the Agents plan, so not applicable here.
  - Verify: both tokens appear in each CLI's output; `$T/hook-claude` exists (and `$T/hook-codex`, if Codex runs hooks); `$T/denied` does not exist; the transcript shows the denial; the sha256 values after undo match those before; the journal entries are listed.
- [ ] **A2 S0.4, Stop and process facts (AC4)**
  - Build:
    - Start an interactive `claude` and `codex` in `$T`.
    - Record `lsof -nP -Fpn -p <codex pid>` (the `thread-writer-locks/<uuid>.lock` mapping) and `ps -o lstart= -p <pid>` against `$T/.claude/sessions/<pid>.json` `procStart`.
    - Stop each from Activity after the confirmation.
    - Then `claude --resume <id>` and the Codex resume.
  - Verify: each session shows in Activity before the Stop; `exited: true`; `ps -p <pid>` is empty; each log resumes; stale-row refusal is already covered by the G2.2 tests (named).
- [ ] **A3 S0.3, TCC**
  - Build:
    - Owner step: `tccutil reset SystemPolicyDocumentsFolder dev.spacevibe.app`.
    - A project at `~/Documents/spacevibe-tcc-probe/.claude/settings.json`, listed in `$T/.codex/config.toml` `[projects]` so the app discovers it.
    - Launch the Developer ID build and open Rules for that project: Allow, then Deny, then a rebuild with Developer ID, then an ad-hoc rebuild.
  - Verify, recorded: which name the prompt shows (SpaceVibe, or the helper; H2); Allow shows the rules; Deny reads "not readable", not empty; the grant survives the Developer ID rebuild and is asked again after the ad-hoc one (B3).
- [ ] **A4 S8.1, offline (AC5).** The owner turns the network off and opens every tab. Verify: every tab renders data with no error banner; PR.2 `no_net_deps` passed.
- [ ] **A5 S8.2, AC1 timing.** The owner finds a permission, removes it and undoes it on the A1 home. Verify: under 60 s, timed by the owner and recorded.
- [ ] **A6 Feature gaps from P1.** Each gap finding has a task or an owner "won't fix". Verify: listed.

### Phase X: cross-platform signal (SV2 timeframe only; no shells)

- [ ] **X1 Cross-compile and Linux CI**
  - Files: new `.github/workflows/core.yml` (ubuntu: setup-go; `sudo mkdir -p /private/tmp && sudo chmod 1777 /private/tmp`; GO; XC)
  - Depends on: G2.4
  - Verify: XC locally. The Linux run happens only after the owner pushes (push needs approval); record its result then.
- [ ] **X2 Windows on real hardware (D-6; needs hardware; unverified until run)**
  - Build: `go test -count=1 ./...` on a real Windows machine. The path-hashed goldens (`inventory`, `mutate`) carry a platform gate, because the B6 hashes are POSIX paths; the gate's comment gives the reason.
  - Verify: the output is pasted; compiling in CI does not count.

### Final

- [ ] **F1 Owner eye approval, one batch (AC6)**
  - Build: in the owner's runtime (W22): the renamed app on the fixture home and on the A1 home (all tabs, About, Settings > Update, the update toast); the old-vs-new shot comparisons from S.1 to S.8; the site build. Open the main sheet (W18).
  - Verify: the owner's words recorded with the date.
- [ ] **Gates (outward-facing; each needs explicit approval when it runs)**
  - GH1: rename the GitHub repo (after D-1), then `git remote set-url`.
  - REL1: a fresh notarization profile and key backup; `scripts/release.sh --notarize` on a clean `main`; then the printed tag, push and `gh release create` (feed asset name decided from the R2 H7 result).
  - GH2: `gh release edit v0.1.0` with the deprecation text and a link to the new download (SV14; after REL1).
  - WEB1: Vercel project for `site/` and a preview deploy; `curl -sI <preview>/live/abc` → `308` with `location: https://active.spacevibe.dev/abc`; an old Hub route → `kyant.dev`.
  - WEB2: repoint `spacevibe.dev`, only after the Hub session confirms `kyant.dev` is verified (SV16 order).
  - WEB3: `dig +short reins.spacevibe.dev`; a redirect is needed only if a record exists (SV16).

## Coverage ledger (filled during G tasks; it gates S.8)

| Swift test file (Tests/ReinsCoreTests) | Go owner task | Swift cases | Go cases |
| --- | --- | --- | --- |
| ZstdStreamTests, LogFilesTests, TailReaderTests | G1.4 | | |
| OrderedJSONTests | G1.2 | | |
| TOMLReaderTests | G1.3 | | |
| FrontmatterTests, InventoryTests, UsageScanTests | G2.1 | | |
| RootsTests, WriteGuardTests | G1.6, G2.3 | | |
| FileEditTests, WriteConcurrencyTests, JournalTests, MutationTransactionTests, MutateTests | G1.7, G2.3 | | |
| RulesTests, RulesGoldenTests | G2.4 | | |
| ActivityTests, ActivitySafetyTests, ActivityGoldenTests, ActivityStopTests, ProcessGuardTests, ActivityPricingTests | G1.1, G1.8, G1.9, G2.2 | | |
| ReadHardeningTests | G1.3, G1.4, G2.1 | | |
| LimitsTests, LimitsStatuslineTests, LimitsGoldenTests | G2.5, G2.6 | | |
| FixtureHomeTests | G1.10 | | |
| ToolchainTests | retired: checks the Swift test toolchain, which `Tests/SpaceVibeTests` still exercises | | n/a |

## Acceptance map

| Requirement | Tasks |
| --- | --- |
| SV1, SV6 | P0.5, G1, G2 |
| SV2 | X1, X2 (signal only) |
| SV3 | PR.1 to PR.3, S.2 |
| SV4 | S.1 to S.8 |
| SV5 | P0.3, P0.4, G1.10, every `TestGolden*`, C1 |
| SV7, SV8 | P1, A1 to A6 |
| SV9, SV11 | R1 to R6, GH1 |
| SV10, SV16 | R5, WEB1 to WEB3 |
| SV12 | R1, P0.5, S.2 |
| SV13 | R2 |
| SV14 | GH2 |
| SV15 | R1 (no migration), R5 (release notes) |
| SV17 | R5 copy review (other products keep their names) |
| AC1 | A5 |
| AC2 | A1 |
| AC3 | R1, G1.6, the `SPACEVIBE_TEST` guard in every Go and Swift test |
| AC4 | G2.2, S.3, A2 |
| AC5 | PR.2 `no_net_deps`, A4 |
| AC6 | F1 |
| AC7 | R2 |
| AC10 | G0.1, G2.5, S.4 |

## Parallelism (all inside this repo, X1)

- Sequential, one session: P0.1 → P0.2 → P0.3 → P0.4 → R1 → P0.5.
- Then independent, safe in parallel sessions because their files do not overlap:
  - P1 (read only);
  - PR.1;
  - each G1.x (its own package directory);
  - G0.1 (`Tests/ReinsCoreTests`);
  - S.1 (Swift UI; conflicts with other UI plans' sessions, see D-5);
  - R2 (plist and scripts; after R1).
- PR.2 after G1.6. G2.1 and G2.2 run in parallel; G2.3 → G2.4; G2.5 after G0.1; G2.6 after D-3.
- The S tasks run in the listed order: each cut-over shares `AppEnvironment` and the shot baseline.
- R3 → R4 → R5 → R6 after S.8. Then A1 to A5 in order, F1, the gates.

## Risks and unknowns (Hypothesis — unverified, with the deciding check)

| ID | Hypothesis | Deciding check |
| --- | --- | --- |
| H1 | `os/user` with `CGO_ENABLED=0` on darwin gives the password-database home even with `HOME` overridden. If it falls back to `$HOME`, the AC3 guard is void. | G1.6 test with `HOME=/tmp/x` on a darwin `CGO_ENABLED=0` build |
| H2 | TCC attributes a `~/Documents` read by the child core to the app, so the prompt names SpaceVibe and the grant is keyed to `dev.spacevibe.app` | A3 |
| H3 | go-toml/v2 rejects at least one `rules-home/codex-*` config | G1.3 scratch run |
| H4 | The ported `resolvedPath` and Swift `realpath(3)` return the same case for mixed-case input on case-insensitive APFS | G1.6 vector built from a mixed-case path |
| H5 | klauspost's errors on truncated or corrupt frames map onto the CZstd outcomes ZstdStreamTests expects | G1.4 |
| H6 | A shell started by Go `os/exec` gets default SIGPIPE behavior and stays in Claude's process group | `scripts/test-statusline.sh` on the Go subcommand (G2.6) |
| H7 | After GH1, v0.1.0 copies follow GitHub's redirect to a feed signed with the new key; what Sparkle then shows is unknown | R2 local feed test |
| H8 | Notarization accepts a Go helper in `Contents/Helpers` built with hardened runtime | `release.sh --notarize` in REL1 (outward: uploads to Apple) |
| H9 | Claude Code keeps credentials outside `CLAUDE_CONFIG_DIR` (Keychain), which changes A1's sign-in step | the owner signs in during A1 setup |
| H10 | Reading NDJSON from a Swift `Pipe` keeps up with a full Activity report every 3 s | time `activity.subscribe` on the A1 home in S.3 |
| H11 | Go's ES6 float text equals JSON.stringify for every number in the goldens (the cost values in `activity.json`) | G1.10 canonical round trip of each golden |
| H12 | Each ICU regex keeps its behavior once ported to RE2 | per-pattern vectors in G1, G2.2, G2.4 |
| H13 | A trash move across volumes needs a copy fallback in Go | G2.3 injected EXDEV, plus one manual check with a project on an external volume |
| H14 | NFD file names reach code that sorts or compares names | G2.1 vector with an NFD skill name |
| H15 | On Windows, B6 path hashes, POSIX modes and `flock` do not apply | X2; out of scope beyond the gate |
| H16 | The Go helper's `vtool` minos differs from 15.0 without harm (only the app executable faces LaunchServices) | P0.5 vtool output, plus a launch on macOS 15 |

## Out of this plan, hand off

- `spacevibe-hub` session: build the Hub on `kyant.dev` and verify it before WEB2 (SV16); then retire `spacevibe-hub` (SV10).
- Workspace session (SV17, X1):
  - the workspace `AGENTS.md` map and `docs/CONTEXT.md`/`docs/ARCHITECTURE.md` lines for this repo;
  - renaming the local folder `spacevibe-workspace/spacevibe-reins`;
  - the fate of Hub `/vote` (Postgres, Neon Auth);
  - the marketing strategy.
- The Agents and Tokens plans re-target their engine tasks to Go once D-5 is answered; their owners record it in those plans.

## Verification evidence

None yet. This plan has run no command.

## Handoff

- Progress: nothing built. The Go spike is reported verified by the owner session on 2026-11-07: klauspost zstd reads the three `.zst` fixtures byte-correct (5.77 MB in about 10 ms); go-toml/v2 parses nested tables; `CGO_ENABLED=0` cross-builds windows and linux on amd64 and arm64. Its evidence is not in the repo (C7).
- Checkout: `main` at 39ff3f5, clean at survey time. The `v0.1.0` tag exists (`.git/refs/tags/v0.1.0`).
- Next action: P0.1 (spec table shown to the owner), then the P0.2 answers to D-2 and D-7.
- Blockers by task:

| Decision | Blocks |
| --- | --- |
| D-7 | P0.3 |
| D-5 | S.1, R3 |
| D-3 | G2.6, S.8 |
| D-1 | R4, R5, GH1 |
| D-4 | the S-R4 wording in R5 |
| D-6 | X2 |
| Q1 (C1) | the parity definition, before G1.10 |
| Q2 (C3) | R6 |

/goal Deliver docs/plans/2026-11-07-go-core-and-spacevibe-identity.md: a Go core in core/ (D-7) that matches every frozen golden by canonical bytes and every ported Swift unit test, driven by the SwiftUI app only through CoreClient over JSON-RPC 2.0 on stdio with version refusal, protocol-only stdout and exit on EOF; ReinsCore, CZstd and the Node oracle deleted; env, data folder, bundle id dev.spacevibe.app and Sparkle key renamed, with the rename report naming every remaining "reins" site; S0.5, S0.4, S0.3, S8.1 and S8.2 (AC1, AC2, AC4, AC5) passed once on the Go core with the final identity, AC3, AC7 and AC10 green, and owner eye approval in F1; stop at decisions D-1 to D-7 and before every outward-facing gate (GitHub rename, v0.1.0 text, release, Vercel or DNS).
