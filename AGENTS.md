> Global standard: ~/.claude v2026-09-29

# Reins

Local app to see and control what Claude Code and Codex CLI are equipped with. Stack: Electron (main process in TypeScript) with a React, Tailwind CSS v4 and shadcn/ui (Base UI) renderer, built by electron-vite. The engine in [core/](core) is plain Node ESM (`.mjs`, JSDoc), unbundled.

## Common commands

| Command             | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `npm run dev`       | App with hot reload. Reads and writes the real `~/.claude` and `~/.codex` |
| `npm run build`     | Builds `out/` (main, preload, renderer)                                 |
| `npm start`         | Runs the built app from `out/` (no dev server)                          |
| `npm run typecheck` | `tsc` for [electron/](electron) and [src/](src)                         |
| `npm test`          | Core and IPC handler tests, against a temporary `HOME`                  |
| `npm run e2e:smoke` | Headless run of the built app against fixture logs ([e2e/smoke.mjs](e2e/smoke.mjs)) |
| `npm run pack`      | Unpacked macOS app in `release/` (`electron-builder --dir`, unsigned)    |

## Layout

- [core/](core): the engine (inventory, usage scan, mutations, journal). Never imports Electron.
- [electron/main.ts](electron/main.ts): app start, window, usage worker. [electron/ipc/](electron/ipc): one file per area, each exports `handlers`; [electron/register-ipc.ts](electron/register-ipc.ts) picks them up by glob.
- [src/lib/ipc-contract.ts](src/lib/ipc-contract.ts): the one list of channels and payload types. A new channel is this file plus one handler file.
- [src/](src): the renderer. It only sees `window.reins.invoke(channel, request)`.
- `web/` is the old prototype. It cannot run any more (its server is gone) and is deleted with the Loadout screen in the [plan](docs/plans/2026-11-02-reins-electron.md) task 4.4.
- `mocks/` holds earlier throwaway mocks kept for reference, outside git. Do not import from them.

## Repo-specific rules

- **R1.** `npm run dev` and `npm start` read and write the real `~/.claude` and `~/.codex`. Agents testing a write must set `HOME` (and `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `REINS_HOME`) to a temporary folder. With `REINS_TEST=1` the app runs headless (no window, counts only on stdout) and `roots()` throws when a root is under the real home.
- **R2.** Screenshots and fixtures from real configs or logs are never committed: they contain real skill names, hook commands and prompts. Keep them in the gitignored `shots/`.
- **R3.** Values in settings files that may be secrets are never read into the UI or logged.
- **R4.** The app never executes a hook or a recorded command.
- **R5.** The built app opens no network listener and loads from `file:`. The renderer reaches `core/` only through the channels in `src/lib/ipc-contract.ts`: the preload refuses any other channel, and main refuses a sender that is not the app's own top frame. The window stays `contextIsolation` + `sandbox`, with navigation and `window.open` denied, no auto-updater and no crash reporter. Do not widen any of these to make a feature easier.

## Known traps

- The CSP in [src/index.html](src/index.html) forbids inline `style` attributes and inline scripts (`style-src 'self'`). Setting `element.style` from React is fine; markup strings with `style=` are not. The dev server gets a looser policy from `electron.vite.config.ts`, so a clean dev console proves nothing: run `npm run build && npm run e2e:smoke`, which fails on any CSP violation.
- `core/` is imported as `#core/*.mjs` (`imports` in `package.json`) and left external by the bundler. A relative path gets rewritten wrongly, and a bundled copy would break the usage Worker, which needs a real file. Packaged, `core/` is `asarUnpack`ed and the Worker path swaps `app.asar` for `app.asar.unpacked` ([electron/lib/worker-path.ts](electron/lib/worker-path.ts)).
- The preload must be CommonJS (`out/preload/index.cjs`): a sandboxed preload cannot be ESM, even though the package is `"type": "module"`. The contract file is bundled into it, so it imports nothing from Node or Electron.
- Errors cross IPC as a value, `{ ok: false, error, status }`, never as a thrown error: `ipcMain.handle` rewrites thrown messages and drops `status`. Unexpected errors log only their code or name, never the message (R3).
- Handlers in `electron/ipc/` must not import `electron`, so `npm test` can run them under plain node. Anything that needs Electron goes in `main.ts`, `register-ipc.ts` or `harden.ts`.
- A hook's identity is the hash of event plus command. Hashing the command alone inflates run counts.
