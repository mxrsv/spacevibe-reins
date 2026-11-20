# Overview

How the app is split between a Go core and a SwiftUI shell, how a request travels, and the Swift-to-Go traps a maintainer would otherwise get wrong. Read this first, then the page for the code you touch ([index](README.md)). Terms follow [GLOSSARY.md](../../GLOSSARY.md).

Requirements: [spec](../specs/2026-11-02-reins.md) and [decision ledger](../specs/2026-11-07-core-port-and-spacevibe-identity-decisions.md) (SV1 to SV17). Execution and progress: [plan](../plans/2026-11-07-go-core-and-spacevibe-identity.md). The wire contract: [core-protocol.md](core-protocol.md).

## Shell and core

- **The core is the engine; the shell is only UI.** The Go binary `spacevibe` ([`core/`](../../core)) reads the CLIs' files, counts usage, watches sessions and makes every write. The SwiftUI app draws state and asks for changes. The shell reaches the core only through one `CoreClient` that spawns it as a child with argv `["rpc"]` and speaks JSON-RPC 2.0 over stdio (SV3, SV4). Nothing in the UI links engine code at the end state.
- **Why a child process, not a library.** A second shell for Windows and Linux is committed (SV2), and the same engine must serve it. A stdio child also keeps the shell free of any listener: the core opens no socket (S-R5).
- **Names come from the core.** The product name, version, env prefix and data folder are one constant each in [`internal/identity`](../../core/internal/identity/identity.go). The shell reads them from `initialize` and hard-codes only the helper's path inside the bundle (SV12).

## Data flow

1. The shell spawns `spacevibe rpc` and sends `initialize`. A protocol-version mismatch is refused and the shell shows a fixed startup-problem text.
2. A screen asks for data: `inventory.read`, `loadout.rows`, `rules.snapshot`, `limits.read`, `activity.read`. The core reads the disk synchronously and answers with plain DTOs; unreadable files become `problems`, never an empty result.
3. Usage is the slow read. `usage.scan` streams `usage/progress`, and the core keeps its result so `loadout.rows` can attach counts without the shell sending them back.
4. Activity is a subscription: one full report, then a full report only when it changed (resync, never deltas).
5. A write (`loadout.*`, `rules.*`) takes the write lock, edits through the atomic-write path, records one journal entry and returns its reference. Undo is `journal.undo` on that id. The same write ends old history: the journal keeps at most 200 entries no older than 30 days, and each entry it drops takes its trash copy with it. Every journal write also sweeps `<data>/trash` under the lock: a folder older than 30 days that no remaining entry names, in any op of any kind, is deleted for good. A delete is only ever a folder directly inside `<data>/trash`, checked by the containment rule Undo uses; one that fails is retried by the next write. Stopping a session is not a journal write and cannot be undone.
6. On stdin EOF the core cancels every in-flight request, waits at most 5 s (a write inside the lock finishes regardless) and exits 0.

## CLI registry and adapters

Every per-CLI fact of the core lives in one of two places ([spec MC-R1](../specs/2026-11-19-multi-cli.md)):

- **The registry**, [`internal/clis`](../../core/internal/clis/registry.go): one `Descriptor` per CLI, pure data. It holds the id, the label, the `Layout` (root folder under `HOME`, the root variable such as `CLAUDE_CONFIG_DIR`, the skills, agents, hook, log and state file names), the `Binaries` it puts on `PATH` (none yet) and the `Concepts` the CLI takes part in. [`config`](../../core/internal/config/config.go) reads each root variable the registry names and `PATH`, and [`roots.Resolve`](../../core/internal/roots/roots.go) places every layout. The registry imports no subsystem. `Layout` gets no new named field (MC29): a file only one CLI has, such as a wave-1 CLI's, is named in that CLI's adapter.
- **One adapter per concept**, in the package that uses it, in files named for the CLI (`claude.go`, `codex.go`, `gemini.go`). Each package defines its own small interface and builds its table once with [`clis.NewAdapters`](../../core/internal/clis/adapters.go). There is no `init()` registration.

| Concept | Interface | Table |
| --- | --- | --- |
| usage | `lineParser` | [usage/adapters.go](../../core/internal/usage/adapters.go) |
| inventory | `inventoryAdapter` (`cliInventory` with `kinds()`, `cliProjects`) | [inventory/adapters.go](../../core/internal/inventory/adapters.go) |
| mutate | `cliWriter` | [mutate/writers.go](../../core/internal/mutate/writers.go) |
| activity | `activityAdapter` (`logFolder`, `sessionSource`, `stopper`) | [activity/adapters.go](../../core/internal/activity/adapters.go) |
| limits | `reader` | [limits/adapters.go](../../core/internal/limits/adapters.go) |
| process match | `proc.CodexMatcher`, asserted from the CLI-neutral `proc.Adapter` by the Codex activity adapter | [proc/codex.go](../../core/internal/proc/codex.go), [activity/codex.go](../../core/internal/activity/codex.go) |

Shared code loops over `InOrder()`, which follows the registry order, and never compares a CLI id. Every per-CLI value on the wire is an array of `{cli, …}` objects in that order ([core-protocol.md](core-protocol.md#wire-types)); Go reads one element with [`clis.Find`](../../core/internal/clis/wire-entries.go), which never answers with another CLI's. Every type takes `clis.ID` directly: no package aliases it. Rules and the status line belong to one CLI by nature, so they look up their CLI's folders with `Roots.CLI` and have no adapter table.

**The shell learns CLI facts from `clis.list`** ([method](core-protocol.md#methods), spec MC27). Each fact is read from the adapter that implements it, so there is no second table to drift: `kinds` from the inventory adapter, the limits reading from the limits reader, `readsSessionLog` from the activity concept, the approval limit from the activity adapter's state function, and the subagent-tools fact from the mutate writer. `installed` is [`clis.Installed`](../../core/internal/clis/detect.go): a stat of the root folder or of a named binary in each absolute `PATH` folder, never a process. The shell keeps only each CLI's look (mark, tone) and which CLIs the owner turned off.

**Per-kind support** ([inventory/kinds.go](../../core/internal/inventory/kinds.go), MC-R5). Each inventory adapter declares every item kind (`skill`, `agent`, `hook`; rules, MCP servers and permissions join `ItemKinds` when an adapter first reads them): support `full`, `readOnly` or `absent`, runs `counted` or `notLogged` with the reason, a copy format, and the hook events. Three readings stay apart and are never shown as 0:

- **absent**: the CLI has no such kind. The cell state is `absent`, not `missing`, and it is never an add or copy target.
- **not measurable**: the CLI has the kind and does not log its runs (Codex hooks). The cell is `unmeasurable` with the reason.
- **unsupported format**: the CLI has the kind but SpaceVibe cannot write it (`readOnly`, a 403 on any write), or its copy format differs from the source's, so a copy is refused (409). Formats are never converted (MC5).

`mutate` enforces the declaration: every add, remove and copy calls `writableKind`, and a copy also needs equal copy formats (`copyAllowed`). Hook rows of two CLIs share a row only when the event names are identical, because the row key hashes event plus command (MC28); there is no mapping between event vocabularies.

**A missing adapter means the concept is absent, never a fallback.** `Adapters.For` and `Roots.CLI` return an error that wraps `clis.ErrUnknownCLI` for an id with no entry, or `clis.ErrConceptAbsent` for a CLI that lacks the concept. Code that once read an unknown id as Codex now returns that error: the fold, the file grouping, the mutate folders, and the Totals, Windows and Cells lookups. `activity.stop` and `loadout.removeDeadHooks` refuse such an id with the same sentence as before (`cli must be claude or codex.`), and the copy `target` with `target must be claude or codex.`, both built from the registry. Do not add a `default:` branch that picks a CLI, and do not skip an id silently.

**Traps.**

- **The registry order is the wire order.** Reports, the limits list and the inventory read follow it, so reordering entries changes the goldens.
- **Gemini CLI is an entry with only the limits concept.** `Roots.CLIs` holds its folder, with every other path empty. Code that ranges over `Roots.CLIs` must not assume a CLI has skills or logs. Range over a concept's adapters instead.
- **A table and the registry can drift.** Each package's `Test…MatchRegistry` runs `Check`, which fails when a CLI lists a concept with no adapter, or when an adapter exists for a CLI without the concept.
- **The shell shows only what `clis.list` lists.** The app's one filter ([`CLICatalogFilter.swift`](../../Sources/SpaceVibe/Components/CLICatalogFilter.swift)) drops every wire value whose `cli` the list did not return, or that the owner turned off, so a CLI added to a report but not to the registry decodes and never shows. With a CLI turned off the shell counts the chips and row flags again by the rule of `FilterCountsOfRows`; [`CLICatalogTests`](../../Tests/SpaceVibeTests/CLICatalogTests.swift) holds the two equal on the fixture home.
- **The real-home guard names the first root it finds**, so its check order is part of the error text: the roots of CLIs whose layout names files, the data folder, the state files, then folder-only roots such as Gemini CLI's ([`roots.Resolve`](../../core/internal/roots/roots.go); `TestErrorDetailsCheckOrder`).
- **A copy names its target.** `loadout.copyToOther` takes `target`; there is no implied "other CLI". The agent copy format `agentFields` is shared by Claude Code and Codex on purpose: the copy carries name, description and instructions, and each writer puts them in its own file, as the frozen `copy-agent-*` scenarios record. A CLI whose agents carry something else declares another format.
- **A test that needs a CLI the registry lacks** extends a copy with `clis.Default().Plus(d)` and builds its table with `clis.NewAdaptersIn`, then swaps the package's table for the test (`TestACLIWithoutHooksGetsAbsentCells`). The real registry is never changed.

**Adding a CLI:**

1. Add an entry to [registry.go](../../core/internal/clis/registry.go). Its position is its wire position. Set `RootEnv` only when the CLI documents such a variable. List only the concepts it really has.
2. For each listed concept, add `<cli>.go` in that package with the adapter, plus one line in the package's table. A CLI whose sessions come from the process table also gets a matcher interface in `proc/<cli>.go`, implemented on `System` and `Fixture`. Its activity adapter asserts that interface from the `proc.Adapter` it is handed and answers `clis.ErrConceptAbsent` without it; `proc.Adapter` itself never changes.
3. In the inventory adapter, declare every kind in `kinds()`, `absent` for one the CLI does not have. Name the CLI's own files there, not in `Layout`. Give a kind a copy format only when a copy carries exactly what another CLI with that format writes.
4. Run `cd core && SPACEVIBE_TEST=1 go test ./...`. The `MatchRegistry` tests check the wiring, `TestKindDeclarationsAreConsistent` the declaration, and the `TestEvery…CLIIsInEachArray` tests that the CLI appears in each wire array. Rerun the contract cases with `-update` (the `clis_list` transcript gains the CLI) and read the diff.
5. In the shell, add only the CLI's look to [`CLIRegistry`](../../Sources/SpaceVibe/Components/CLIRegistry.swift): an id constant, an entry in `looks`, the mark in `Resources/Brand` and the tone in `PaletteValue`. Its label and every other fact reach the shell through `clis.list`, and no wire type needs a new case. `scripts/test.sh` runs [`CLIRegistryTests`](../../Tests/SpaceVibeTests/CLIRegistryTests.swift), which fails until every CLI of the `clis_list` transcript has a complete look.
6. Give the CLI its synthetic fixture under the fixture home, and update the goldens on purpose ([Where the fixtures and goldens live](#where-the-fixtures-and-goldens-live)): `GOLDENTEST_UPDATE=1` makes `TestGoldenInventory` and `TestGoldenUsage` rewrite their golden, then check every changed value, update `SHA256SUMS` and the digest.

## Where the fixtures and goldens live

| What | Where |
| --- | --- |
| Frozen goldens | [`core/testdata/fixtures/golden/`](../../core/testdata/fixtures/golden), listed with their hashes in [`SHA256SUMS`](../../core/testdata/fixtures/SHA256SUMS) |
| Synthetic homes the goldens ran on | [`core/testdata/fixtures/`](../../core/testdata/fixtures): `home`, `activity-home`, `rules-home`, `zst` |
| Materializer, canonical writer, diff, leak guard, freeze check | [`core/internal/goldentest`](../../core/internal/goldentest); rules in [core-protocol.md](core-protocol.md#canonical-golden-writer) |
| Recorded request and response transcripts | [`core/testdata/rpc/*.jsonl`](../../core/testdata/rpc), recorded and compared by the contract tests in `core/cmd/spacevibe`; the Swift `CoreTypesTests` decode every response into its DTO |

The materialized home sits at the fixed path `/private/tmp/reins-fixture-home`, and the fixture keeps its own `.reins` folder. Hook and project ids in the goldens are hashes of absolute paths under that root. The Node generator is gone; only `inventory.json` and `usage.json` can be rewritten from the Go result (`GOLDENTEST_UPDATE=1`, [golden-update.go](../../core/internal/goldentest/golden-update.go)), and only on purpose: the freeze check fails until `SHA256SUMS` is updated by hand. Step 0b used it once, with a value-by-value check that every Claude Code and Codex value stayed the same (plan MC-T6). Renaming the root or the folder breaks the goldens; the rename report lists them as skipped sites (C3). Parity means canonical bytes of a named projection, not the Node bytes; the plan's "Parity method" lists the projections.

## Swift-to-Go traps

Condensed; the plan's [full list](../plans/2026-11-07-go-core-and-spacevibe-identity.md#swift-to-go-traps-seen-in-the-code) has line references.

- **JSON.** `encoding/json` reorders keys, escapes `<>&` and U+2028, and quotes input in its errors. Config files go through [`ojson`](../../core/internal/ojson) (byte round trip, splice edits, last duplicate wins, depth 256), not through a struct.
- **JavaScript text rules.** Trimming, splitting, lengths and sort order follow JS (UTF-16 units, U+FEFF counted as space). `strings.TrimSpace`, `strings.Fields` and `unicode.IsSpace` give different answers.
- **Regex.** ICU patterns become RE2: no lookaround, `\s` lacks `\v`, `$` does not match before a final newline. Every pattern gets vectors.
- **Paths.** `Roots.resolvedPath` resolves the deepest existing ancestor of a missing path; `filepath.EvalSymlinks` fails on it. The real home comes from the password database, never `HOME` or `os.UserHomeDir`, or the real-home guard (S-R1, AC3) is void.
- **Writes.** An atomic write is a `O_EXCL` temp file, `fchmod`, `fsync`, read-back, a byte re-check, rename, and `unlink` on failure ([`fsx`](../../core/internal/fsx)). A symlinked target stays a link. A trash move across volumes needs a copy fallback, because `os.Rename` returns EXDEV.
- **Locks.** Go's mutex is not re-entrant: split each write into a locked entry and an unlocked body. Two processes write the same data folder, so the lock also takes `flock` on `<data>/write.lock`.
- **Lines and sizes.** `bufio.Scanner` stops at 64 KB; log lines go up to 32 MiB in the usage scan and 16 MiB in the tail readers that Activity and Limits use ([tail-reader.go](../../core/internal/logs/tail-reader.go)), and zstd streams are capped at 512 MiB.
- **Equality.** Swift compares strings by canonical equivalence; Go compares bytes. A decomposed file name can sort or match differently.
- **Numbers.** Swift and Go print floats differently. Bytes on disk differ; parsed values agree. Only the golden writer needs JavaScript's text.
