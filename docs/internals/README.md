# Internals

Reference pages for `ReinsCore`: what each subsystem is responsible for, where its facts come from, and what the code does not show. Read the page for the code you touch; skip the rest. Terms follow [GLOSSARY.md](../../GLOSSARY.md).

| Subsystem | Page | Source |
| --- | --- | --- |
| Skills, subagents and hooks installed for both CLIs, and their usage cells | [inventory.md](inventory.md) | `Inventory*.swift`, `Frontmatter.swift`, `Roots.swift` |

Planned pages (usage scan and pricing, mutations and journal, limits, activity, rules) are tracked in the [plan](../plans/2026-11-07-reins-internals-docs.md); a page is added to this table when it exists.

## Maintain a page

Update the owning page in the same change when a documented responsibility, interface, state transition, runtime path, compatibility rule or failure behavior changes. A refactor that keeps the contract needs no prose change.

Keep each fact in one page and link to it from elsewhere. Link to files and named symbols; do not copy implementation. Explain what a signature does not: meaning, constraints, traps. Document current behavior only; planned changes stay in specs and plans.
