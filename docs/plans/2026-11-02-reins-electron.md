# Reins: move to Electron and build the Matrix interface

Spec: [2026-11-02-reins.md](../specs/2026-11-02-reins.md) (requirements, platform, interface, acceptance criteria AC1 to AC6).
Status: planned, nothing implemented. Written 2026-11-02.

## Approach

Keep `core/` as the engine and put an Electron shell around it. Today `server.mjs` serves `web/` over `127.0.0.1:4328`; the shell replaces that with IPC, so the built app opens no network listener.

```
core/                 existing, pure Node ESM, stays .mjs. Imported by the main process. Gains rules.mjs and activity.mjs.
electron/             main.ts, preload.ts, ipc/<area>.ts (thin handlers, validate input, call core/)
src/                  renderer: React + TypeScript + Tailwind + shadcn/ui (Base UI)
  components/ui/      shadcn primitives, restyled through tokens, not hand-edited per screen
  components/{loadout,rules,activity,shell}/
  lib/ipc-contract.ts the one place channel names and payload types are defined
test.mjs              core tests (node --test), temp HOME only
e2e/                  Playwright `_electron` specs, temp HOME only
```

Layout follows the "Vite + Tauri desktop" block of `~/.claude/templates/project-structure.md`, with `electron/` in place of `src-tauri/`.

Tooling (verified 2026-11-02, not yet exercised): `electron-vite` 6 on Vite 6 to 8, `electron` 45.2.1, shadcn CLI 4.23 (`npx shadcn@latest init -b base -t vite`; Base UI is shadcn's default since the July 2026 changelog). Package manager stays npm, as in `AGENTS.md`.

## Decisions made in this plan (reversible)

- Main process and renderer in TypeScript; `core/` stays JavaScript with JSDoc, imported unbundled.
- `usage.mjs` runs as a `worker_threads` Worker started from a real file path. Under electron-vite that means the `?modulePath` import and, in the packaged app, `asarUnpack` for `core/`. A bundled copy would break the worker.
- The "no network listener" rule applies to the built app: it loads from a `file:` or custom protocol, with no auto-updater and no crash reporter. The dev server listens on localhost in development only.
- Window security: `contextIsolation`, `sandbox`, no `nodeIntegration`, an allow-list of IPC channels, navigation and `window.open` blocked, CSP set.
- Stop in Activity is a placeholder until the owner decides.

## Decision needed

- **Rules grid writes.** The approved grid sets Allow, Ask or Deny per capability per CLI, but neither CLI stores a capability verdict. Claude Code stores concrete `permissions.allow/ask/deny` entries, a bare `Bash` deny overrides narrower allows, and a "mixed" cell has no single value to write. Options: (A) the segmented control writes one tool-wide rule (`Bash`, `Edit`, `Read`, `WebFetch`) after a preview of the rules it replaces, is disabled on "mixed" cells, and Undo restores the previous arrays; (B) the grid is display-only and edits happen on the concrete rules below it. Recommendation: A for cells with a faithful mapping, B everywhere else, decided after the Codex schema is read (task 0.1). Phase 5 is blocked on this.

## Tasks

Phases 1 to 4 can start now. Phase 5 waits on 0.1 and the decision above. Phase 6 waits on 0.3.

### Phase 0: verification spikes (evidence goes under each task)

- [ ] 0.1 Read the real Codex permission schema (`config.toml` keys, per-project trust, rules files). Do not reuse the mock's `approval_policy`, `sandbox_mode`, `network_access`; they are mock data. Verifies the spec's first "to verify" item. Gates 5.
- [ ] 0.2 In a throwaway `HOME`, write a skill, agent, hook and permission with `core/` and confirm a real `claude` and `codex` session honors each (AC2). Needs the owner: see Action needed.
- [ ] 0.3 Find how to read live Codex session state without a status file (log tail, process list). If it cannot be measured, Activity shows "not measurable" with the reason (AC4). Gates 6.
- [ ] 0.4 Electron spike: run `scan()` through the `?modulePath` worker inside `electron-vite dev` and in a packaged build; record Electron's bundled Node version against the APIs `core/` uses. Gates 2.
- [ ] 0.5 Audit `core/` for macOS-only assumptions. Evidence so far: no `process.platform` or `/Users/` paths in `core/*.mjs` (grep, 2026-11-02). Windows stays out of this plan.

### Phase 1: baseline and scaffold

- [ ] 1.1 Baseline commit before any move: `core/`, `test.mjs`, `server.mjs`, `web/`. Check every path against `AGENTS.md` R2 first (no real-config fixtures, no `shots/`; `mocks/` holds `shots/` folders that `.gitignore` excludes, confirm nothing else real is inside). `npm test` is 14/14 on 2026-11-02. Commit with explicit paths.
- [ ] 1.2 Scaffold electron-vite with React and TypeScript, then `shadcn init -b base -t vite`, Tailwind, and the test and lint scripts. Commit.
- [ ] 1.3 Rewrite `AGENTS.md` (D8). These lines become false: "Node 24 stdlib, no build step, no dependencies"; the `npm start` port row; R5 (loopback server, `x-reins` header), replaced by an IPC rule; the CSP trap, which still applies if mock templates with inline `style=` are ported. Keep R1 to R4.
- [ ] 1.4 Test guard for AC3: with `REINS_TEST=1`, `roots()` throws when a resolved root is under the real `os.userInfo().homedir`. A unit test proves it refuses.

### Phase 2: main process and IPC

- [ ] 2.1 Move the `/api/inventory`, `/api/history`, `/api/item` and action endpoints of `server.mjs` into `electron/ipc/*`, with the contract in `src/lib/ipc-contract.ts`. Each handler validates input and keeps the error shape (`UserError`).
- [ ] 2.2 Handler tests against a temp `HOME`, reusing the `test.mjs` fixtures. Delete `server.mjs` and its tests once the handlers cover the same cases.
- [ ] 2.3 Window hardening listed under Decisions, with a test that a non-allow-listed channel and a navigation are refused.

### Phase 3: shell and tokens (UI gate)

- [ ] 3.1 Window with hidden-inset title bar, sidebar (Loadout, Rules, Activity), top bar, hint bar, light and dark. Tokens come from the mock's `reins.css`, mapped to the shadcn variables.
- [ ] 3.2 `⌘K` command palette and a toast with Undo, wired to the core journal.
- [ ] 3.3 Screenshots (dark and light) to `~/scratch/spacevibe-reins/`; owner eye approval before the commit. Run the `quality-gates` check on the shared controls.

### Phase 4: Loadout (UI gate)

- [ ] 4.1 Fixture tests first for the known defects: hook error count shows 0 while the logs hold 20 error records; project-level `.claude/` configuration is not read. Then fix them.
- [ ] 4.2 Matrix table: grouped by Skills, Agents, Hooks; filter chips; the five usage states (counted, never ran, not counted yet, not measurable, not installed); "Add to <CLI>" in the missing cell; remove and copy with Undo; plugin-owned rows read-only.
- [ ] 4.3 Codex hook runs are not logged, so they render as "not measurable" with the reason on hover.
- [ ] 4.4 Owner eye approval, then delete `web/` and the prototype notes in `AGENTS.md`.

### Phase 5: Rules (UI gate; blocked on 0.1 and the decision)

- [ ] 5.1 `core/rules.mjs`: read and write Claude Code permissions (global and per-project `settings.json`, `settings.local.json`) and the Codex keys confirmed in 0.1. Secret values (`env` and similar) are never read. Every write goes through the existing journal. Tests per cell and per CLI: file, key, and the Undo result.
- [ ] 5.2 Capability grid, concrete rules list and scope selector as decided.
- [ ] 5.3 Owner eye approval.

### Phase 6: Activity (UI gate; blocked on 0.3)

- [ ] 6.1 Port live-session parsing and metrics from `agent-world/` in the `model-lab` repo into `core/activity.mjs` (read-only on logs). Tests on fixture logs.
- [ ] 6.2 Failed commands grouped with a count and one title form; file history with paths long enough to tell two files apart; junk-title fallback; worktree slug not shown as a project; "next run passed" never presented as a fix. Replay Studio findings from the spec.
- [ ] 6.3 One lane per CLI as in the mock, with "not measurable" where 0.3 says so. No Stop button.
- [ ] 6.4 Owner eye approval.

### Phase 7: package and accept

- [ ] 7.1 Build a macOS package with electron-builder; `core/` unpacked from the asar; no auto-updater. Signing and notarization are release work, not in this plan.
- [ ] 7.2 Playwright `_electron` e2e with temp `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `REINS_HOME`; the 1.4 guard is on. Cover Loadout, Rules and Activity flows and Undo.
- [ ] 7.3 AC5: run the packaged app with the network off and open all three tabs.
- [ ] 7.4 AC1: owner times the permission task (find, remove, undo) under one minute.
- [ ] 7.5 Update `README.md` and `CHANGELOG.md` if they exist (D12). Mark this plan historical with the date and commit range (D1).

## Acceptance map

| AC | Covered by |
| --- | --- |
| AC1 find, remove, undo a permission in a minute | 5.2, 7.4 |
| AC2 CLI honors what the app writes | 0.2, 7.2 (writes), real-CLI check by owner |
| AC3 tests never touch the real config | 1.4, 7.2 |
| AC4 running session of each CLI, limits stated | 0.3, 6.3 |
| AC5 works offline | 7.3 |
| AC6 owner approves the UI by eye | 3.3, 4.4, 5.3, 6.4 |

## Action needed from the owner

- 0.2: run a real `claude` and a real `codex` session against the throwaway config (needs your logins). The agent prepares the config and the checklist.
- Eye approval at 3.3, 4.4, 5.3, 6.4 and the AC1 timing at 7.4.

## Handoff

- Checkout: `main` at `21a2a01`, working tree: `core/`, `mocks/`, `server.mjs`, `test.mjs`, `web/` untracked; this plan file new.
- Observed: `npm test` 14 pass, 0 fail (2026-11-02, temp HOME). Mock for the chosen direction: `~/scratch/spacevibe-reins/b-matrix.html` (outside the repo).
- Remaining: everything above. Blockers: the Rules-grid decision, 0.1 and 0.3.

`/goal` Deliver the Reins Electron app per docs/specs/2026-11-02-reins.md: complete docs/plans/2026-11-02-reins-electron.md phases 0 to 7 so that AC1 to AC6 hold, with every UI phase approved by the owner by eye, tests running only against temp HOME, and each task's evidence recorded under it; stop and ask at the Rules-grid decision, at owner-only steps, and before any push, merge or release.
