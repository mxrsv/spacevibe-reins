# Reins: Limits

Spec: [2026-11-02-reins.md](../specs/2026-11-02-reins.md) (Interface: Limits; Scope: Limits; acceptance criteria AC5, AC6, AC10).
Parent plan: [the SwiftUI plan](2026-11-02-reins-swiftui.md), whose packaging and cut-over phases still apply.
Mock: `~/scratch/spacevibe-reins/limits/index.html`, outside git, synthetic data, typical and edge data in light and dark;
its direction B is the target. Placement B, chosen by the owner on 2026-11-03: a sidebar block on every tab, detail in a
popover.
Status: engine done (L1), placement picked (L2); L3 to L5 open. Started 2026-11-03.

## Approach

The engine reads what the CLIs already write and nothing else; the app polls it and draws one surface.

```
Sources/ReinsCore/  Limits (types, entry, Gemini), LimitsClaudeCache, LimitsCodexLogs; Roots gains claudeState and gemini
Sources/Reins/Limits/  LimitsModel, LimitsWording, the view(s) of the chosen placement
Tests/ReinsCoreTests/LimitsTests.swift, Tests/ReinsTests/LimitsWordingTests.swift
```

Facts this plan rests on, read 2026-11-03 on the owner's Mac:

- Codex 0.166 writes `payload.rate_limits` into every `token_count` event: `primary` and `secondary` with `used_percent`,
  `window_minutes`, `resets_at` (epoch seconds), plus `plan_type`. Older rollouts used `resets_in_seconds`.
- Claude Code 2.1.317 keeps `cachedUsageUtilization` in `~/.claude.json`: `fetchedAtMs` and `utilization.limits[]` with
  `kind`, `group`, `percent`, `resets_at` (ISO 8601, microseconds), `scope.model.display_name`, `is_active`. Its other keys
  are code names and dollar amounts. The owner's copy was fetched 2026-11-01 while the file was written 2026-11-03, so
  Claude Code does not refresh it per session.
- Gemini CLI 0.63 keeps no quota under `~/.gemini`; its numbers come only from Google's internal `retrieveUserQuota` call.
- No Kimi CLI on this Mac: only Superset's wrapper `~/.superset/bin/kimi` and `~/.kimi-code/config.toml` with hooks.
- `spacevibe-board` wraps Claude Code's `statusLine` on this Mac to capture quota (checked 2026-11-03: the command names it). Reins must not install a
  second wrapper or read Board's capture folder (workspace rule: no shared data between repos).

## Decisions made in this plan (reversible)

- **Strict shapes.** One Claude entry or Codex window in a shape the reader does not know makes the whole CLI unreadable,
  never a shorter list: a missing window could be the one nearly used up.
- **Codex: newest three logs by modification time, last 4 MB each.** A resumed session appends to its old file, so path
  order is wrong. The real read takes about 60 ms over 2,122 logs.
- **The app shows share left, like a battery**, and tints at 20% left (warn) and 5% left (danger). The lead figure is the
  tightest current, active window.
- **A Claude reading older than 6 hours carries a warn tag** with its age and the `/usage` hint; it is still shown.

## Tasks

### L1. Spec and engine (done 2026-11-03)

- Spec scope, constraints and AC10 updated; `PRODUCT.md` purpose line.
- `Limits.read(_:)` returns Claude Code, Codex, Gemini CLI with states measured, not recorded, unreadable, not measurable,
  not installed. `Roots.claudeState` follows `CLAUDE_CONFIG_DIR`; both new paths are under the REINS_TEST guard.
- Verification: `scripts/test.sh --filter "Limits|Roots"` → `Test run with 24 tests in 3 suites passed`. Full run: 359 of
  360 pass; the one failure (2 issues) is in `ActivityFormatTests.swift`, another session's uncommitted test. A scratch binary outside
  the repo read the real home: Claude Code and Codex measured, Gemini CLI not measurable, in 0.063 s.

### L2. Placement (done 2026-11-03)

The owner picked B (sidebar block on every tab, detail in a popover) and no Limits tab. The spec's Interface and shell
lines record it. Consequences for the tasks below:

- Gemini CLI appears on every tab, as the third tile of the block and a card in the detail; the spec line now allows it
  there and nowhere else.
- `SidebarView`, `ShellCommands` and `Components/` belong to the design-language session (`spacevibe-reins-6c`): the block
  slot, the new borderless tile component and `⌘L` need its go-ahead.
- `LimitsModel` lives at app scope (created beside `ShellModel`) and is injected through the environment, because every
  tab shows the block.

### L3. Model and wording

- `LimitsModel` (`@MainActor`, observable, app scope): reads `Limits.read` off the main thread at launch, when the window
  becomes key, every 60 s while the window is visible, and on Refresh. A read never blocks the UI and never throws to it.
- `LimitsWording`: share left, tone, "Resets in 3 h 12 min · 21:12", "read 2 days ago", the state lines, window names
  (`5-hour`, `Weekly`, `Weekly · <model>`, unknown length → the record's own name). A passed reset reads "unknown".
  Also the short states the sidebar tiles use ("no reading", "not installed", "not measurable", "unreadable") and the stale
  marker (reading older than 6 hours).
- Tests in `LimitsWordingTests` against fixed dates. AC10 wording half.

### L4. View

- Built only from `Sources/Reins/Components` and `ReinsType` roles; no style literal in the screen folder
  (`StyleBoundaryTests`, which must see `Sources/Reins/Limits/`). Sidebar block, detail popover (card per CLI, tile per
  window, tightest leading) as in mock direction B.
- Shell edits (`SidebarView`, `ShellCommands` for `⌘L`) and the new tile component are coordinated with the design-language
  session first; message it before touching them. The tile is borderless (fill and space), a step from the v2 card rules.
- `Copy /usage` copies text only; nothing is run (S-R4).

### L5. Shots and eye approval

- Light and dark, typical and edge data from a `TempHome` with synthetic files, through the existing shot harness.
- `impeccable distill` and `clarify` on the surface.
- Owner eye approval. AC6.

## Verification map

| AC | Check |
| --- | --- |
| AC5 | No request exists to make: `LimitsTests` "start no request and no process"; app launched offline shows the surface |
| AC6 | L5 eye approval |
| AC10 | `LimitsTests` (engine) and `LimitsWordingTests` (unknown after reset, not measurable wording) |

## Handoff

- Checkout: `main`, shared with the design-language session (`spacevibe-reins-6c`), which owns
  `Sources/Reins/{Components,Tokens,Gallery,Loadout,Activity,Rules,Shell}`. Commit with `git commit -- <paths>`.
- Remaining: L3 to L5.

`/goal` Build Reins Limits per docs/specs/2026-11-02-reins.md: complete docs/plans/2026-11-03-reins-limits.md tasks L3 to L5 in placement B (recorded under L2), so that AC10 holds in scripts/test.sh and the surface matches ~/scratch/spacevibe-reins/limits/ in light and dark shots; stop and report if the shell owner has not agreed to the sidebar and component edits, and never send a request, read a credential, start a CLI, push or release.
