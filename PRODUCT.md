# Reins

Register: product

## Product purpose
A local macOS tool to control Claude Code and Codex CLI: what each agent is equipped with, what it is allowed to do, and what it did. It shows every skill, subagent and hook with how often each one actually ran according to local logs, and lets a developer add or remove one in seconds. Most people pile these up from GitHub and never learn which ones fire or what runs on each event.

## Users
A developer or vibe coder who runs Claude Code and Codex daily and has collected dozens of skills, agents and hooks. They open it when installing something new, when a session feels slow or noisy, or when cleaning up. Desk, beside an editor and terminal. Today the owner is the only user and judges the interface by eye.

## Mechanism
One inventory across both CLIs, joined to usage counted from local session logs: installed but never invoked, invoked often, present in one CLI and missing in the other, and exactly which hook commands fire on each event.

## Brand personality
Direct, tidy, a little opinionated. It says plainly what is unused and what cannot be measured.

## Anti-references
Generic AI dashboards, neon on black, gradients, card grids of icon + title + text, marketplace storefronts, terminal costumes, settings-page sprawl.

## Design principles
- Usage is evidence: counted, not counted yet and not measurable look different.
- Rows compared by eye on bars beat hero tiles; severity is tinted in context.
- Every control performs a real action, and adding or removing is one step with a visible way back.
- Nothing is executed: a hook is shown and written, never run by the app.

## Accessibility and constraints
Keyboard navigation, visible focus, WCAG AA, reduced motion. Offline, no account, no telemetry. Writes go only to the skill, agent, hook and permission locations of Claude Code and Codex; each write keeps a restorable copy. Plugin-owned items are read-only. Secret values in settings are never read or displayed.

## Distribution
Public site and downloads: `reins.spacevibe.dev` (not live yet). The app itself runs only on this Mac at `127.0.0.1`; no user data passes through the site.
