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
5. A write (`loadout.*`, `rules.*`) takes the write lock, edits through the atomic-write path, records one journal entry and returns its reference. Undo is `journal.undo` on that id. Stopping a session is not a journal write and cannot be undone.
6. On stdin EOF the core cancels every in-flight request, waits at most 5 s (a write inside the lock finishes regardless) and exits 0.

## Where the fixtures and goldens live

| What | Where |
| --- | --- |
| Frozen goldens | [`core/testdata/fixtures/golden/`](../../core/testdata/fixtures/golden), listed with their hashes in [`SHA256SUMS`](../../core/testdata/fixtures/SHA256SUMS) |
| Synthetic homes the goldens ran on | [`core/testdata/fixtures/`](../../core/testdata/fixtures): `home`, `activity-home`, `rules-home`, `zst` |
| Materializer, canonical writer, diff, leak guard, freeze check | [`core/internal/goldentest`](../../core/internal/goldentest); rules in [core-protocol.md](core-protocol.md#canonical-golden-writer) |
| Recorded request and response transcripts | [`core/testdata/rpc/*.jsonl`](../../core/testdata/rpc), recorded and compared by the contract tests in `core/cmd/spacevibe`; the Swift `CoreTypesTests` decode every response into its DTO |

The materialized home sits at the fixed path `/private/tmp/reins-fixture-home`, and the fixture keeps its own `.reins` folder. Hook and project ids in the goldens are hashes of absolute paths under that root, and nothing can regenerate them now that the Node generator is gone. Renaming the root or the folder breaks the goldens; the rename report lists them as skipped sites (C3). Parity means canonical bytes of a named projection, not the Node bytes; the plan's "Parity method" lists the projections.

## Swift-to-Go traps

Condensed; the plan's [full list](../plans/2026-11-07-go-core-and-spacevibe-identity.md#swift-to-go-traps-seen-in-the-code) has line references.

- **JSON.** `encoding/json` reorders keys, escapes `<>&` and U+2028, and quotes input in its errors. Config files go through [`ojson`](../../core/internal/ojson) (byte round trip, splice edits, last duplicate wins, depth 256), not through a struct.
- **JavaScript text rules.** Trimming, splitting, lengths and sort order follow JS (UTF-16 units, U+FEFF counted as space). `strings.TrimSpace`, `strings.Fields` and `unicode.IsSpace` give different answers.
- **Regex.** ICU patterns become RE2: no lookaround, `\s` lacks `\v`, `$` does not match before a final newline. Every pattern gets vectors.
- **Paths.** `Roots.resolvedPath` resolves the deepest existing ancestor of a missing path; `filepath.EvalSymlinks` fails on it. The real home comes from the password database, never `HOME` or `os.UserHomeDir`, or the real-home guard (S-R1, AC3) is void.
- **Writes.** An atomic write is a `O_EXCL` temp file, `fchmod`, `fsync`, read-back, a byte re-check, rename, and `unlink` on failure ([`fsx`](../../core/internal/fsx)). A symlinked target stays a link. A trash move across volumes needs a copy fallback, because `os.Rename` returns EXDEV.
- **Locks.** Go's mutex is not re-entrant: split each write into a locked entry and an unlocked body. Two processes write the same data folder, so the lock also takes `flock` on `<data>/write.lock`.
- **Lines and sizes.** `bufio.Scanner` stops at 64 KB; log lines go up to 32 MiB and zstd streams are capped at 512 MiB.
- **Equality.** Swift compares strings by canonical equivalence; Go compares bytes. A decomposed file name can sort or match differently.
- **Numbers.** Swift and Go print floats differently. Bytes on disk differ; parsed values agree. Only the golden writer needs JavaScript's text.
