# Reins: move to Electron and build the Matrix interface

Spec: [2026-11-02-reins.md](../specs/2026-11-02-reins.md) (requirements, platform, interface, acceptance criteria AC1 to AC6).
Status: in progress. Core, IPC, all four UI areas and Stop are built (2026-11-02); the UI waits for the owner's eye approval and is uncommitted. Written 2026-11-02.

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

## Decision needed

- **Rules grid writes.** The approved grid sets Allow, Ask or Deny per capability per CLI, but neither CLI stores a capability verdict.
  - Claude Code stores concrete `permissions.allow/ask/deny` entries, a bare `Bash` deny overrides narrower allows, and a "mixed" cell has no single value to write.
  - Codex (0.166, task 0.1) has two mutually exclusive models: legacy `sandbox_mode` plus `[sandbox_workspace_write]`, or `default_permissions` with `[permissions.<name>]` profiles. Network is set in different places in each. "Push and deploy" has no Codex setting; only a command-prefix rule in `~/.codex/rules/*.rules` can approximate it.
  - Options: (A) on Claude Code, the segmented control writes one tool-wide rule (`Bash`, `Edit`, `Read`, `WebFetch`) after a preview of the rules it replaces, is disabled on "mixed" cells, and Undo restores the previous arrays; Codex cells are display-only and link to the real keys (`approval_policy`, `sandbox_mode`, `network_access`, project `trust_level`, rules); (B) the whole grid is display-only and edits happen on the concrete rules and keys below it.
  - Recommendation: A, with Codex cells always display-only and a plain "unrestricted" state when the file has `sandbox_mode = "danger-full-access"` (this machine's setup). Phase 5 is blocked on this decision only.

## Tasks

Phases 1 to 4 can start now. Phase 5 waits on the decision above (0.1 is done). Phase 6 is unblocked (0.3 done).

### Phase 0: verification spikes (evidence goes under each task)

- [x] 0.1 Codex permission schema, done 2026-11-02 (read-only research by a subagent against `codex-cli 0.166.0` and its config JSON schema at tag `rust-v0.166.0`; key names in the local `config.toml` and the 74 rules were spot-checked, the rest is as reported).
  - Real keys: `approval_policy` (`on-request`, `never`, or a `granular` table; `untrusted` is retired), `sandbox_mode` (`read-only`, `workspace-write`, `danger-full-access`), `sandbox_workspace_write.{network_access, writable_roots}`, `approvals_reviewer`, `default_permissions` plus `[permissions.<name>.{filesystem,network}]`, `projects."<path>".trust_level`, `web_search`, `shell_environment_policy`, per-MCP `approval_mode`.
  - The mock's `network_access` is wrong as a top-level key. `default_permissions` and `sandbox_mode` must not both be present; Reins picks one model per file and warns.
  - Rules: `~/.codex/rules/*.rules` (Starlark `prefix_rule(... decision="allow|prompt|forbidden")`), project rules only for trusted projects; an `allow` means "runs outside the sandbox without a prompt".
  - Precedence: CLI flags, project `.codex/config.toml`, profile file, `~/.codex/config.toml`, cloud, `/etc/codex`, defaults. Untrusted projects skip project-level `.codex/`.
  - Capability mapping: Read and Edit are per path only in a `[permissions]` profile; Run commands only via rules and `approval_policy`; Network per profile; Push and deploy has no setting; Secrets only by `deny` globs (beta; issue openai/codex#22179 says an `.env` glob did not block `cat .env`, unverified on macOS in 0.166).
  - Writing: there is no `codex config` subcommand; the file is 93 KB, mode 600, with 62 projects, 9 MCP servers and `[hooks.state.*]` tables that Codex itself rewrites, plus a `config.toml.bak`. Reins needs a format-preserving TOML editor (core only has a reader, `tomlFields`), a backup, an atomic write, mode 600 kept, and a re-parse after writing. Concurrent rewrites by a running Codex are unverified.
  - This machine runs `approval_policy = "never"` with `sandbox_mode = "danger-full-access"`, so the Codex column would read "unrestricted" for file and network.
- [ ] 0.2 In a throwaway `HOME`, write a skill, agent, hook and permission with `core/` and confirm a real `claude` and `codex` session honors each (AC2). In the same run, press Stop on one session of each CLI: confirm it exits on SIGTERM, that its log still resumes, and whether a child of a running tool (a dev server started from Bash) survives. Only `entrypoint: cli` sessions have been seen so far (13 of 13 live, process name `claude`); a session hosted by another app is unverified. Needs the owner: see Action needed.
- [x] 0.3 Live session state, done 2026-11-02 (read-only research by a subagent; the paths, the 108 rollouts, the lock files and the `agent-world` file list were spot-checked, the rest is as reported and unverified on a live running turn).
  - Claude Code: `~/.claude/sessions/<pid>.json` is a status file (`status` idle, busy, shell). `statusUpdatedAt` goes stale during a long busy turn, so show age from the transcript's last write. A permission prompt is not distinguishable from `busy`.
  - Codex: no status file. State comes from the rollout tail (`task_started`, `task_complete`, `turn_aborted`); the live `codex` process holds `~/.codex/thread-writer-locks/<threadId>.lock`, so `lsof` on the pid maps process to rollout exactly (better than `agent-world`'s cwd match; launch modes other than the CLI are unverified). The log has no heartbeat during a tool call, and approval waits are not recorded. A live process before its first prompt has no rollout.
  - Cost: both CLIs log tokens; Codex `total_token_usage` has input including cached and output including reasoning; Claude usage must be deduplicated by `message.id`. Show it as "estimated, API-equivalent". Needs a maintained per-model price table (`agent-world/server/pricing.json` is a starting point).
  - Portable from `agent-world/server/`: `tail-reader.js`, `session-state.js`, `live-metrics.js`, `pricing.json`; replace `codex-source.js` matching with the lock-fd mapping.
  - UI wording for what cannot be measured is part of 6.3.
- [x] 0.4 Electron spike: run `scan()` through the `?modulePath` worker inside `electron-vite dev` and in a packaged build; record Electron's bundled Node version against the APIs `core/` uses. Gates 2.
- [x] 0.5 Audit `core/` for macOS-only assumptions. Evidence so far: no `process.platform` or `/Users/` paths in `core/*.mjs` (grep, 2026-11-02). Windows stays out of this plan.

### Phase 1: baseline and scaffold

- [x] 1.1 Baseline commit before any move: `core/`, `test.mjs`, `server.mjs`, `web/`. Check every path against `AGENTS.md` R2 first (no real-config fixtures, no `shots/`; `mocks/` holds `shots/` folders that `.gitignore` excludes, confirm nothing else real is inside). `npm test` is 14/14 on 2026-11-02. Commit with explicit paths. Done 2026-11-02 as `96a7967`; `mocks/` stays untracked (scan clean) pending the owner's call.
- [x] 1.2 Scaffold electron-vite with React and TypeScript, then `shadcn init -b base -t vite`, Tailwind, and the test and lint scripts. Commit.
- [x] 1.3 Rewrite `AGENTS.md` (D8). These lines become false: "Node 24 stdlib, no build step, no dependencies"; the `npm start` port row; R5 (loopback server, `x-reins` header), replaced by an IPC rule; the CSP trap, which still applies if mock templates with inline `style=` are ported. Keep R1 to R4.
- [x] 1.4 Test guard for AC3: with `REINS_TEST=1`, `roots()` throws when a resolved root is under the real `os.userInfo().homedir`. A unit test proves it refuses.

### Phase 2: main process and IPC

- [x] 2.1 Move the `/api/inventory`, `/api/history`, `/api/item` and action endpoints of `server.mjs` into `electron/ipc/*`, with the contract in `src/lib/ipc-contract.ts`. Each handler validates input and keeps the error shape (`UserError`).
- [x] 2.2 Handler tests against a temp `HOME`, reusing the `test.mjs` fixtures. Delete `server.mjs` and its tests once the handlers cover the same cases.
- [x] 2.3 Window hardening listed under Decisions, with a test that a non-allow-listed channel and a navigation are refused.

### Phase 3: shell and tokens (UI gate)

- [ ] 3.1 Window with hidden-inset title bar, sidebar (Loadout, Rules, Activity), top bar, hint bar, light and dark. Tokens come from the mock's `reins.css`, mapped to the shadcn variables.
- [ ] 3.2 `⌘K` command palette and a toast with Undo, wired to the core journal.
- [ ] 3.3 Screenshots (dark and light) to `~/scratch/spacevibe-reins/`; owner eye approval before the commit. Run the `quality-gates` check on the shared controls.

### Phase 4: Loadout (UI gate)

- [x] 4.1 Fixture tests first for the known defects: hook error count shows 0 while the logs hold 20 error records; project-level `.claude/` configuration is not read. Then fix them.
- [ ] 4.2 Matrix table: grouped by Skills, Agents, Hooks; filter chips; the five usage states (counted, never ran, not counted yet, not measurable, not installed); "Add to <CLI>" in the missing cell; remove and copy with Undo; plugin-owned rows read-only.
- [x] 4.3 Codex hook runs are not logged, so they render as "not measurable" with the reason on hover.
- [ ] 4.4 Owner eye approval, then delete `web/` and the prototype notes in `AGENTS.md`.

### Phase 5: Rules (UI gate; blocked on the decision)

- [x] 5.1 `core/rules.mjs`: read and write Claude Code permissions (global and per-project `settings.json`, `settings.local.json`); read the Codex keys and rules confirmed in 0.1 and write only what the decision allows, through a format-preserving TOML editor. Secret values (`env` and similar) are never read. Every write goes through the existing journal. Tests per cell and per CLI: file, key, and the Undo result.
- [ ] 5.2 Capability grid, concrete rules list and scope selector as decided.
- [ ] 5.3 Owner eye approval.

### Phase 6: Activity (UI gate; unblocked by 0.3)

- [x] 6.1 Port live-session parsing and metrics from `agent-world/` in the `model-lab` repo into `core/activity.mjs` (read-only on logs). Tests on fixture logs.
- [ ] 6.2 Failed commands grouped with a count and one title form; file history with paths long enough to tell two files apart; junk-title fallback; worktree slug not shown as a project; "next run passed" never presented as a fix. Replay Studio findings from the spec.
- [ ] 6.3 One lane per CLI as in the mock, with "not measurable" where 0.3 says so.
- [ ] 6.5 Stop on a session row, confirmed first (spec, decided 2026-11-02). Core `stopSession` finds the pid from the system at call time and sends SIGTERM; built and tested with fakes and a child process, real CLI reaction open under 0.2. Eye approval with 6.4.
- [x] 6.6 Read compressed Codex rollouts (`.jsonl.zst`) in the usage scan and Activity, and stop counting interleaved or inherited Codex totals. Found while reviewing TokenTracker on 2026-11-02: 1,941 of this machine's 2,052 rollouts were compressed and unread.
- [ ] 6.4 Owner eye approval.

### Phase 7: package and accept

- [x] 7.1 Build a macOS package with electron-builder; `core/` unpacked from the asar; no auto-updater. Signing and notarization are release work, not in this plan. Done 2026-11-02: `npm run pack` builds `release/mac-arm64/Reins.app`, its headless test mode passes, and its bundled Node 24.22.1 reads `.jsonl.zst` through the unpacked `core/log-files.mjs`.
- [ ] 7.2 Playwright `_electron` e2e with temp `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `REINS_HOME`; the 1.4 guard is on. Cover Loadout, Rules and Activity flows and Undo.
- [ ] 7.3 AC5: run the packaged app with the network off and open all three tabs.
- [ ] 7.4 AC1: owner times the permission task (find, remove, undo) under one minute.
- [ ] 7.5 Update `README.md` and `CHANGELOG.md` if they exist (D12). Mark this plan historical with the date and commit range (D1).

## Progress log (2026-11-02)

Built by parallel subagents; the orchestrator re-ran `npm run typecheck`, `npm test` (103 pass, 0 fail), `npm run build` and `npm run e2e:smoke` (ok, CSP 0 errors, 0 style tags) after the last change. Other figures below are the agents' reports.

- Done and committed: 1.1 to 1.4, 2.1 to 2.3 (server and loopback removed, `AGENTS.md` rewritten, Electron 45.2.1 bundles Node 24.22.1, worker scan verified in dev, built and unpacked runs), 4.1 (hook error root cause: `hook_blocking_error` keeps the command under `attachment.blockingError.command`; project `.claude/` read; 20 errors on the owner's real logs), 4.3 cells, 5.1 core rules, 6.1 core activity, and `fix(core)` for never-ran vs dead counts and `Read(*)` as wide.
- Built, not committed, waiting for eye approval: 3.1 to 3.3 shell and shared blocks, 4.2 Loadout, 5.2 Rules, 6.2 and 6.3 Activity (screenshots in `~/scratch/spacevibe-reins/shots/{shell,loadout,rules,activity}/`). Commit by area after approval, then 4.4 deletes `web/`.
- Still open: 0.2 (owner runs a real `claude` and `codex` on the throwaway config), 1.2 lint script, Phase 7, tooltip and focus-ring screenshots (headless cannot show them).
- Stop and compressed logs, same day: with real logs and a temporary `REINS_HOME`, the scan now covers 2,052 Codex sessions back to 2026-03-29 (81 s first run, 94 ms cached); Activity reads 14 days in 1.4 s. Screenshots in `~/scratch/spacevibe-reins/shots/stop/`.
- Interpretations kept: option A for the Rules grid (Claude writes, Codex display-only); each Rules scope is one settings file; the confirm dialog always opens; the Loadout toolbar says "Counted from N sessions since <date>" instead of "Last 30 days".

### Debt accepted (optimize later)

- Performance: first wide Activity read measured 28 s (a 2-day first read now runs in a worker; the 2-day/40-file window is a guess); `readActivity` log walk is synchronous inside the worker; renderer bundle is 1.0 MB (lucide barrel); `filterCounts` and `buildRows` recompute per call.
- Structure: the Activity worker is an eval string (needs a `core/activity-worker.mjs`); `REINS_TEST` harness ships in the main bundle; IPC types are hand-written with some `any`; module-level store in Loadout; the UI blocks `ScopeSelect`, `Notice`/`Banner`, `ReasonTip`, `NativeSelect`/`TextField`, format helpers should move to `src/components/`.
- Correctness gaps: hook failures without `uuid`/`toolUseID` collapse into one row; project hooks share counts with global ones; Rules grid shows one file only (a project scope hides an inherited Global deny); JSON edits re-serialize the file; rule text and failure reasons are not masked; `Bash(git *)` counts as Run commands only; Codex cell mapping unverified against a live Codex; pending heuristic uses file mtime.
- Gaps: no Playwright `_electron` e2e (plan 7.2), `npm audit` 15 moderate, package unsigned, `@fontsource-variable/geist` unused dependency, `shadcn add` needs `paths` in the root `tsconfig.json`, "Add to <CLI>" button lacks a row-specific `aria-label`.
- Found outside this repo: the owner's `~/.codex/hooks.json` holds 220 dead hooks (28 distinct commands) pointing into temp folders named `deck-e2e-*`; probably left by SpaceVibe Deck e2e runs (cause not checked).

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

- Checkout: `main`; the UI (3.x, 4.2, 5.2, 6.2, 6.3, 6.5) and its IPC stay uncommitted in the working tree until eye approval. `mocks/` stays untracked.
- Mock for the chosen direction: `~/scratch/spacevibe-reins/b-matrix.html` (outside the repo).
- Remaining: owner eye approval (3.3, 4.4, 5.3, 6.4), 0.2, the Rules-grid decision, 1.2 lint script, 7.2 to 7.5.

`/goal` Deliver the Reins Electron app per docs/specs/2026-11-02-reins.md: complete docs/plans/2026-11-02-reins-electron.md phases 0 to 7 so that AC1 to AC6 hold, with every UI phase approved by the owner by eye, tests running only against temp HOME, and each task's evidence recorded under it; stop and ask at the Rules-grid decision, at owner-only steps, and before any push, merge or release.
