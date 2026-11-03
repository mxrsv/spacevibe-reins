# Reins

Register: product

## Product purpose
A local macOS tool to control Claude Code and Codex CLI: what each agent is equipped with, what it is allowed to do, and what it did. It shows every skill, subagent and hook with how often each one actually ran according to local logs, and lets a developer add or remove one in seconds. Most people pile these up from GitHub and never learn which ones fire or what runs on each event. It also keeps a local token and cost history for both CLIs, so no separate tracker is needed. And it shows how much of each subscription's usage limit is left, from the files Claude Code and Codex already write; Gemini CLI keeps none, and the app says so instead of guessing.

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
- Cost is an estimate and says so; a model with no price reads as not measured, never as 0.
- Nothing is executed: a hook is shown and written, never run by the app.

## Accessibility and constraints
Keyboard navigation, visible focus, WCAG AA, reduced motion. Works offline, no account, no telemetry. Writes go only to the skill, agent, hook and permission locations of Claude Code and Codex, plus the app's own data folder; each write to agent configuration keeps a restorable copy. Plugin-owned items are read-only. Secret values in settings are never read or displayed.

## Distribution
Public site and downloads: `reins.spacevibe.dev` (not live yet). The app is a native macOS app (Swift and SwiftUI) that opens no network listener. Its only network requests check for and download updates, once a day and without asking; installing takes a click. No user data passes through the site.
