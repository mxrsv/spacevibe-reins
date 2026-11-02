> Global standard: ~/.claude v2026-09-29

# Reins

Local app to see and control what Claude Code and Codex CLI are equipped with. Stack: Node 24 stdlib, vanilla ES modules, no build step, no dependencies.

## Common commands

| Command      | Purpose                          |
| ------------ | -------------------------------- |
| `npm start`  | App on `127.0.0.1:4328`          |
| `npm test`   | Tests, against a temporary `HOME` |

## Mocks

`mocks/` holds earlier throwaway mocks kept for reference: `replay-studio` (port 4327, reads real logs) and `loadout` (port 4328, writes real configs, data in `~/.loadout`). Do not import from them. Port what is needed into the app.

## Repo-specific rules

- **R1.** `npm start` reads and writes the real `~/.claude` and `~/.codex`. Agents testing a write must set `HOME` (or `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `REINS_HOME`) to a temporary folder.
- **R2.** Screenshots and fixtures from real configs or logs are never committed: they contain real skill names, hook commands and prompts. Keep them in the gitignored `shots/`.
- **R3.** Values in settings files that may be secrets are never read into the UI or logged.
- **R4.** The app never executes a hook or a recorded command.
- **R5.** The server stays loopback-only. Every POST requires the `x-reins` header and a same-origin `Origin`.

## Known traps

- The CSP forbids inline style attributes: bar widths are set from `data-w` in `web/app.js`.
- A hook's identity is the hash of event plus command. Hashing the command alone inflates run counts.
