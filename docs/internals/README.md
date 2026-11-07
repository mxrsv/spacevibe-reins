# Internals

Reference pages for the engine (the Go core): what each subsystem is responsible for, where its facts come from, and what the code does not show. Start with [overview.md](overview.md); then read the page for the code you touch and skip the rest. Terms follow [GLOSSARY.md](../../GLOSSARY.md).

| Subsystem | Page | Source |
| --- | --- | --- |
| Shell and core split, data flow, fixtures and goldens, Swift-to-Go traps | [overview.md](overview.md) | `core/`, `Sources/SpaceVibe` |
| Stdio protocol between the shell and the core: framing, lifecycle, errors, every method and its JSON | [core-protocol.md](core-protocol.md) | `core/internal/rpc` (PR.2), `core/internal/goldentest` |
| Skills, subagents and hooks installed for both CLIs, and their usage cells | [inventory.md](inventory.md) | `core/internal/inventory`, `core/internal/roots` |

Planned pages (usage scan and pricing, mutations and journal, limits, activity, rules) are tracked in the [plan](../plans/2026-11-07-reins-internals-docs.md); a page is added to this table when it exists.

## Maintain a page

Update the owning page in the same change when a documented responsibility, interface, state transition, runtime path, compatibility rule or failure behavior changes. A refactor that keeps the contract needs no prose change.

Keep each fact in one page and link to it from elsewhere. Link to files and named symbols; do not copy implementation. Explain what a signature does not: meaning, constraints, traps. Document current behavior only; planned changes stay in specs and plans.
