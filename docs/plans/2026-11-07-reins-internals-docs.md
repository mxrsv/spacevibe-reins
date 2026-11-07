# Reins: internals reference pages

Requirements: agreed in chat on 2026-11-07, no spec. Scope: one reference page per `ReinsCore` subsystem, so an agent reads only the page for the code it touches. Model: magpie's `docs/subsystems/` (a page per subsystem with a responsibilities and sources-of-truth table, an index, "update the page in the same PR") and orca's "read only when the task touches it" index.
Checkout: `spacevibe-reins` on `main`. Commit with `git commit -- <paths>` only.
Status: not started. Approved so far: the model above and the `AGENTS.md` read-when list (done 2026-11-07).

## Decision needed before T1 (D3)

`docs/internals/` is a valid directory but does not exist yet. D3 and F2 require the owner's yes before a new directory. The owner said "ok" to this plan in chat on 2026-11-07; treat T1 as cleared only if that covers the directory, otherwise ask once.

## Page shape

Each page, English, under `docs/internals/<subsystem>.md`:

1. One paragraph: what the subsystem is for.
2. Table: part, responsibility, source (link to file or named symbol).
3. Source of truth: which file or log each fact is read from.
4. Main runtime paths and state transitions (usage cell states, journal write, lock).
5. Constraints and traps that code does not show (for example the hook identity hash, `.jsonl.zst` rollouts).
6. Failure behavior, compatibility, and the test command that exercises it.

Link to symbols, do not copy implementation. Use the terms of [GLOSSARY.md](../../GLOSSARY.md).

## Tasks

| Task | Page | Source area |
| --- | --- | --- |
| T1 | `docs/internals/README.md`: index table (subsystem to page), maintenance rule | none |
| T2 | `inventory.md` | `Inventory*.swift`, `Frontmatter.swift`, `Roots.swift` |
| T3 | `usage.md` | `UsageScan*.swift`, `LogFiles.swift`, `TailReader.swift`, `ZstdStream.swift`, `Pricing.swift` |
| T4 | `mutations.md` | `Mutate*.swift`, `Journal*.swift`, `FileEdit*.swift`, `WriteLock.swift`, `OrderedJSON.swift`, `TOMLReader.swift` |
| T5 | `limits.md` | `Limits*.swift`, `StatuslineSetup.swift` |
| T6 | `activity.md` | `Activity*.swift`, `ProcessAdapter.swift`, `SessionTitles.swift` |
| T7 | `rules.md` | `Rules*.swift` |
| T8 | Move "Known traps" from `AGENTS.md` into the matching pages and link back; run the doc scripts | `AGENTS.md` |

Each of T2 to T7 is one commit. Write from the code and the Node oracle's behavior, not from memory; a claim a page cannot link to is left out (D6). Pages describe current behavior only; planned work stays in specs and plans.

## Verification

- `bash ~/.claude/scripts/docs-compliance.sh` and `bash ~/.claude/scripts/docs-anchors.sh` pass with no new warning.
- Every source link in a page resolves.
- T8: each trap exists in exactly one place.

## Acceptance

- Every `ReinsCore` file belongs to one page's source column or is named as out of scope in the index.
- `AGENTS.md` points to the index, and no fact in a page is duplicated in `AGENTS.md`.
- Owner agrees the pages let an agent skip unrelated code, on one sample task per page.

## Handoff

2026-11-07: plan written. Next: T1 after the directory is cleared.

/goal Write the Reins internals reference per docs/plans/2026-11-07-reins-internals-docs.md: tasks T1 to T8 in order, one commit each. Done means every ReinsCore file is covered by one docs/internals page, the docs-compliance and docs-anchors scripts print no new warning, every source link resolves, and the AGENTS.md "Known traps" live only in their pages.
