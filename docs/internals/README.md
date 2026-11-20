# Internals

Reference pages for the engine (the Go core): what each subsystem is responsible for, where its facts come from, and what the code does not show. Start with [overview.md](overview.md); then read the page for the code you touch and skip the rest. Terms follow [GLOSSARY.md](../../GLOSSARY.md).

| Subsystem | Page | Source |
| --- | --- | --- |
| Shell and core split, data flow, fixtures and goldens, Swift-to-Go traps | [overview.md](overview.md) | `core/`, `Sources/SpaceVibe` |
| Stdio protocol between the shell and the core: framing, lifecycle, errors, every method and its JSON | [core-protocol.md](core-protocol.md) | `core/internal/rpc` (PR.2), `core/internal/goldentest` |
| Skills, subagents and hooks installed for both CLIs, and their usage cells | [inventory.md](inventory.md) | `core/internal/inventory`, `core/internal/roots`, `core/internal/hashes` |
| Usage scan: which skills, subagents and hooks ran, the scan cache, and the price table behind cost estimates | [usage.md](usage.md) | `core/internal/usage`, `core/internal/logs`, `core/internal/pricing` |
| Limits: how much of each usage Window is left per CLI, and the status-line capture that records Claude Code's | [limits.md](limits.md) | `core/internal/limits`, `core/internal/statusline` |
| Mutations: every write to a CLI's configuration, the journal, Undo, restorable copies, the write lock, and the JSON and TOML handling writes depend on | [mutations.md](mutations.md) | `core/internal/mutate`, `core/internal/fsx`, `core/internal/ojson`, `core/internal/toml` |
| Activity: sessions running now, their titles, failed commands and open tool calls, and Stop | [activity.md](activity.md) | `core/internal/activity`, `core/internal/proc`, `core/internal/textjs`, `core/internal/redact` |
| Rules: the permission entries of Claude Code's settings, the capability grid, and the read-only summary of Codex permissions | [rules.md](rules.md) | `core/internal/rules` |

A new subsystem gets its page and its row in this table in the same change.

Packages with no page of their own: `core/cmd/spacevibe` (the entry point; its methods are in [core-protocol.md](core-protocol.md)), [`clis`](../../core/internal/clis/registry.go) (the CLI registry, see [overview.md](overview.md#cli-registry-and-adapters)), [`config`](../../core/internal/config/config.go) (the only place the core reads the environment), [`coreerr`](../../core/internal/coreerr/coreerr.go) (errors whose message is safe to show, see [core-protocol.md](core-protocol.md)) and [`identity`](../../core/internal/identity/identity.go) (the product's names, one constant each).

## Maintain a page

Update the owning page in the same change when a documented responsibility, interface, state transition, runtime path, compatibility rule or failure behavior changes. A refactor that keeps the contract needs no prose change.

Keep each fact in one page and link to it from elsewhere. Link to files and named symbols; do not copy implementation. Explain what a signature does not: meaning, constraints, traps. Document current behavior only; planned changes stay in specs and plans.
