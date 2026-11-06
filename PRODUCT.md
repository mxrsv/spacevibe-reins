# Reins

Register: product

## Product purpose
A local macOS tool to control Claude Code and Codex CLI: what each agent is equipped with, what it is allowed to do, and what it did. It shows every skill, subagent and hook with how often each one actually ran according to local logs, and lets a developer add or remove one in seconds. Most people pile these up from GitHub and never learn which ones fire or what runs on each event. It also keeps a local token and cost history for both CLIs, so no separate tracker is needed. And it shows how much of each subscription's usage limit is left, from local Claude Code status-line snapshots and Codex session logs; Gemini CLI keeps none, and the app says so instead of guessing.

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
- Every control performs a real action, and adding or removing is one step (one save for a panel of agent settings) with a visible way back.
- Cost is an estimate and says so; a model with no price reads as not measured, never as 0.
- Nothing is executed: a hook is shown and written, never run by the app.

## UX principles
Rules under the look; global ones are `~/.claude/rules/quality/ux.md` (UX1-UX4). Reins applies them like this:
- **Jobs, in priority order; a higher one wins a conflict.** 1. Clean up: find what is never used and remove it. 2. Balance the two CLIs: add what one lacks. 3. Control: which hook fires on which event, which permission is open. 4. Watch: usage left, sessions running.
- **Vocabulary, one word one meaning.** `CLI` is Claude Code or Codex (Gemini CLI where it is shown). `Agents` are subagents only; a CLI is never called an agent. `Skill`, `Subagent`, `Hook`, `Rule` and `Window` (a usage limit window) name one thing each; never a generic "item" in a label.
- **Colour, one meaning.** Green, amber and red are reserved for state (fine, needs attention, danger). Category colours (Skills, Agents, Hooks), CLI identity (Claude clay, Codex mono) and the accent (blue) use other hue families and never reuse a state colour.
- **Flow: detection and action sit together.** A problem shown in a row (never ran, dead) offers its fix in the same row within one hover or click (the warning popover with `Remove`). Every write has Undo; `Stop` in Activity is the one write without undo and names the pid and the consequence in a confirmation.

## Accessibility and constraints
Keyboard navigation, visible focus, WCAG AA, reduced motion. Works offline, no account, no telemetry. Writes go only to the configuration and instruction files of Claude Code and Codex (settings and permissions, hooks, MCP servers, model, skills, subagents, `CLAUDE.md` and `AGENTS.md`), plus the app's own data folder; each write to agent configuration keeps a restorable copy. Plugin-owned items and managed settings are read-only. Secret values are never displayed or logged; one can be replaced without being shown.

## Distribution
Public site and downloads: `reins.spacevibe.dev` (not live yet). The app is a native macOS app (Swift and SwiftUI) that opens no network listener. Its only network requests check for and download updates, once a day and without asking unless turned off in Settings; installing takes a click. No user data passes through the site.
