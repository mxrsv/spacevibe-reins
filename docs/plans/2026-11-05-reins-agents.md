# Reins: Agents

Spec: [2026-11-05-reins-agents.md](../specs/2026-11-05-reins-agents.md), AG1 to AG10.
Depends on [design language v4](2026-11-05-reins-design-language-v4.md) V5 (the components) before any UI task here. The core tasks A1 to A6 can start now.
Mock: [`mocks/agents/agents-panel.html`](../../mocks/agents/agents-panel.html) (C′), with the v4 look at [`mocks/agents/controls.html`](../../mocks/agents/controls.html)`?icons=tabler&buttons=a`. Both are tracked with synthetic data, and A12 deletes the folder.
Checkout: `spacevibe-reins` on `main`, shared with other sessions. Commit with `git commit -- <paths>` only.
Started 2026-11-05. Status: the owner approved the write approach below on 2026-11-05 (W9, "ok"), adding that every failure shows a toast. The owner also picked the name-based secret rule the same day. The owner picked the A0b mock on 2026-11-05 ("ok chốt"), so A1 can start; the cut-over (A12) is the only owner stop left.

## Approach

```
Sources/ReinsCore/   SecretMask, TOMLEdit, ClaudeSettingsEdit (any key path), ClaudeStateMCP (~/.claude.json), MCPFile
                     (.mcp.json), CodexConfigEdit, CodexRulesFile, CodexHooksFile, InstructionFile; every save goes
                     through Journal
Sources/Reins/Components/  InspectorPanel (resize, footer, discard prompt), MarkdownEditor + Preview, CodeEditor (gutter,
                     masked values), MenuPicker; CardButton and the verdict picker come from v4
Sources/Reins/Agents/      AgentsTab, AgentsScreen, AgentCard, one view per panel and CLI, AgentsModel (drafts, scopes, diff)
Sources/Reins/App/LaunchMode, Shell/TabRegistry   the development switch REINS_AGENTS=1
```

### Write approach and recovery (W9)

- **One path for every write.** Each panel builds its new file bytes in memory. One save becomes one `Journal` entry, with a `file-edited` op per file: the old bytes go to the trash first, then each file is replaced by `FileEditAtomicWrite`.
  - Undo uses the same machinery Loadout and Rules use today.
  - A failure partway through rolls back the ops already done, the same as `Journal.recordMutation`.
- **Smallest edit.**
  - JSON files (`settings.json`, `.mcp.json`, `hooks.json`, and the `mcpServers` of `~/.claude.json`) are edited through `OrderedJSON`, which splices only the changed region.
  - `config.toml` goes through a new `TOMLEdit`. It can set, remove and append a key in a table, and add or remove a table or an array item. It keeps every other line byte-identical, and its result must read back through `TOMLReader` and equal the intended value, or the write is aborted.
- **`~/.claude.json` concurrency.**
  - Record the size, modification time and SHA-256 of the bytes that were read.
  - Just before the rename, read the file again. If any of the three changed, apply the same `mcpServers` edit to the new bytes and check again; give up after one retry with the spec's message.
  - The file's other keys are never parsed into a model.
- **Secrets.**
  - `SecretMask` finds secret spans by key path and returns masked text plus a span table that never leaves `ReinsCore`.
  - On save it maps each placeholder back to its original span, and refuses a placeholder that moved.
  - Errors carry a position or a fixed reason, never content (S-R3).
  - The trash copies already hold whole files. They stay inside the app's data folder, whose mode is confirmed as 0600 in A1.
- **Guards.**
  - Codex: a write that would leave both `sandbox_mode` and `default_permissions` set is refused.
  - Plugin-owned items and managed settings have no write path at all.
  - A `.rules` file that holds anything other than `prefix_rule` calls and comments is read-only.
- **Recovery.**
  - Every save can be undone from the toast or from the journal, after a relaunch too.
  - A failed write leaves the target untouched, because the temp file is removed before any rename.
  - Tests run only against `TempHome` (S-R1). A manual check uses the synthetic home from `scripts/dev-fixture.sh --prepare`, opened with `open -n build/Reins.app --env HOME=… --env CLAUDE_CONFIG_DIR=… --env CODEX_HOME=… --env REINS_HOME=… --env REINS_TEST=1 --env REINS_AGENTS=1`. `REINS_TEST=1` keeps the S-R1 guard: `Roots.resolve` throws when a root resolves under the real home.
  - The real `~/.claude` and `~/.codex` are never touched by this work.

## Tasks

- [x] A0. Spec and plan.
- [x] A0b. Before any code, read Codex's `default_permissions` schema and add the profile editor and the both-models state to mock C′; the owner then picks them (AG6). The schema was read and the mock built on 2026-11-05, at `mocks/agents/agents-panel.html#open=codex/permissions&codex=profiles` and `&codex=both`. The owner picked it on 2026-11-05 ("ok chốt").
- [ ] A1. `SecretMask` for JSON and TOML: detection (all of an MCP server's env and headers, elsewhere by key name), mask, unmask-merge, and the moved-placeholder refusal. Also confirm the mode of the data folder and the trash (AG3).
- [ ] A2. `TOMLEdit` with golden tests for comments, dotted keys, inline tables, multi-line arrays and quoted table names (AG5).
- [ ] A3. `ClaudeSettingsEdit` at all three scopes:
  - `defaultMode`, `additionalDirectories` and `model`;
  - rules and hooks through the existing code;
  - the whole-file Advanced save with mask merge;
  - managed settings read-only (AG2, AG3).
- [ ] A4. MCP: `ClaudeStateMCP` for user and local `~/.claude.json` entries, with the concurrency check, and `MCPFile` for `<p>/.mcp.json`. Covers AG4 and AG3 for env and headers.
- [ ] A5. `CodexConfigEdit`:
  - approval, sandbox, network, writable roots, trust, model, effort, `mcp_servers`;
  - profiles and the both-models guard;
  - the Advanced save.

  Also `CodexRulesFile` (patterns shown, add, change and remove) and `CodexHooksFile` (AG2, AG5, AG6).
- [ ] A6. `InstructionFile`: read and write `CLAUDE.md`, `CLAUDE.local.md` and `AGENTS.md`, and resolve `@path` imports relative to the file and `~`. Plus one journal entry per save across files (AG2).
- [ ] A7. Components:
  - `InspectorPanel`: push layout, 420 to 720 pt with remembered widths, cards at least 440 pt, the footer and the discard prompt;
  - `MarkdownEditor` with Preview;
  - `CodeEditor` with a gutter and masked spans;
  - `MenuPicker`.

  Each gets a gallery specimen (AG7, AG8).
- [ ] A8. The Agents screen behind `REINS_AGENTS=1`, while Rules stays the default.
  - The switch is honoured in debug builds, and in any build only when `REINS_TEST=1` is also set.
  - The second case lets the owner test the release bundle from `scripts/build-app.sh` on a synthetic home. No user sets both, and `REINS_TEST=1` makes `Roots.resolve` refuse the real home.
  - The A8 screen covers:
    - the cards and panel routing;
    - per-panel scopes remembered per agent;
    - drafts, the review dialog, the toast with Undo, and the error toasts;
    - the Claude Code panels (AG1, AG2, AG7).
- [ ] A9. The Codex panels, including the profile editor and the both-models state picked in A0b (AG6).
- [ ] A10. Shots: `REINS_SHOT_SCREEN=agents` for every panel, both appearances, with drafts, confirmations and errors. Extend `StyleBoundaryTests` to cover `Agents/`. Synthetic fixture homes through `scripts/fixture-home.mjs` (S-R2) for:
  - Codex legacy, profiles and both models;
  - MCP `env` and `headers`, plus a plain `DISABLE_TELEMETRY`;
  - a dead hook.

  The variants are picked by `REINS_FIXTURE_AGENTS=legacy|profiles|both`, which the `swift` workflow already loops over once `Sources/Reins/Agents` exists. Then write a "Test tomorrow" list in Handoff: one launch command per fixture, verified, and what to click.
- [ ] A11. Real-CLI check, run with the owner like the parent plan's S0.5: a throwaway home needs the owner's sign-in, and real sessions spend their quota. `claude` and `codex` load a permission, a hook, an MCP server, a model and an instruction-file change written by Reins (AG9).
- [ ] A12. Cut-over:
  - run `impeccable distill` and `clarify`, then get the owner's eye approval of the shots next to the mock (AG10);
  - in the same change, remove the switch, the Rules tab and its code, Loadout's hooks, and `mocks/agents/` once design language v4 V8 is approved (AG1);
  - update `AGENTS.md` (S-R3 wording, the screen list), `docs/DESIGN-LANGUAGE.md`, and the parent spec's status.

## Verification

- `scripts/test.sh`, which must report more than 0 passed.
- `scripts/build-app.sh`, which must print `minos 15.0`.
- `REINS_SHOT_SCREEN=agents scripts/dev-fixture.sh --shots <dir>`.
- The manual run on a synthetic home with `REINS_AGENTS=1`.

## Handoff

2026-11-05: the plan is written, and the owner approved the write approach and the secret rule. The owner picked the A0b mock. Next: design language v4 V2 to V5, then A1. Every failed save maps to an error toast in A8 and A9 (AG7).

2026-11-04 (cloud session, unattended; checkout `claude/reins-agents`, branched from `claude/reins-design-v4`): A1 to A10
are written and committed, one commit each, and **none is verified**: the design language v4 runs lost their macOS runner
twice in the Test step (see that plan's Handoff), so per the brief no Agents commit was pushed for its own run and no box is
ticked. The branch is pushed once, with `[skip ci]` on its last commit.

- **Commits:** A1 `58a2553` SecretMask and TOMLLayout, A2 `5a229dc` TOMLEdit, A3 `6a0e05d` AgentSave and ClaudeSettingsEdit,
  A4 `f5b92c4` MCP, A5 `9374c8c` Codex config, rules and hooks, A6 `9368abf` InstructionFile, A7 `a6380dc` components, A8
  `18d78ca` the page and the Claude Code panels, A9 `74fc6ff` the Codex permissions panel, A10 `f6f451f` the style
  boundary and the fixture notes, then this note.
- **Not run anywhere:** `scripts/test.sh`, `scripts/build-app.sh`, the `agents` shots. The sandbox has no Swift (and
  `download.swift.org` is refused), so every Swift line is unchecked by a compiler. Expect compile fixes first.
- **Checked here:** the fixture variants write (`REINS_FIXTURE_AGENTS=legacy|profiles|both node scripts/fixture-home.mjs`),
  and `node scripts/make-golden.mjs` gives no diff (the variants run only when the variable is set).
- **A1 data folder:** the trash folders are created 0700 and the copies 0600 (`Trash.slot`, `FileEdit.apply`); a test pins
  it (`SecretMaskTests.trashMode`).
- **Codex profile layout, Hypothesis — unverified:** the schema page could not be read from here, so the TOML layout follows
  mock C′: `[permissions.<name>]` `extends`, `[permissions.<name>.filesystem]` path = access,
  `[permissions.<name>.network]` `enabled`, `[permissions.<name>.network.domains]` host = access, and `[features]`
  `network_proxy`. Check it against https://learn.chatgpt.com/docs/permissions.md in A11.
- **Next:** on the owner's Mac, `scripts/test.sh` and `scripts/build-app.sh`, fix what they report, then the "Test
  tomorrow" list; tick A1 to A10 with a green run id, the test line and `minos 15.0`; then A11 and A12.

Departures from mock C′ and the spec:

- The panel's width is remembered for the run (per Advanced and the other panels), not across launches.
- The hint bar keeps the shell's own `⌘K Search or run` and `Esc Close` around the page's hints.
- "Models seen in the logs" counts the first model each of the 400 newest logs names (`ModelUsage`).
- The Hooks card counts every hook of the CLI, all scopes, not Global only.
- A rule's verdict menu ("Move to …", Remove) is a SwiftUI menu on the tag; headless shots draw the tag alone, as with every menu.
- Changing a rule's verdict is one draft item (`moveRule`), read "Change" in the review.
- Loading in the review's Save: the spinner sits over the label.
- Open in editor and Show in Finder go through `NSWorkspace` (the file's default app, and Finder).
- A blank Claude settings file opens in Advanced as `{}`.

### Test tomorrow

Each block prepares a synthetic home and opens the release bundle on it. `--prepare` prints `export HOME='<home>'` and the
other exports and keeps the home; put that path in place of `<home>`. Build first: `scripts/build-app.sh`.

| Fixture | Prepare |
| --- | --- |
| Codex legacy (`sandbox_mode`), MCP `env` and `headers`, token-like keys, a plain `DISABLE_TELEMETRY`, two dead hooks | `REINS_FIXTURE_AGENTS=legacy scripts/dev-fixture.sh --prepare` |
| Codex profiles (`default_permissions = "project-edit"`) | `REINS_FIXTURE_AGENTS=profiles scripts/dev-fixture.sh --prepare` |
| Codex with both models | `REINS_FIXTURE_AGENTS=both scripts/dev-fixture.sh --prepare` |

Then, for each: `open -n build/Reins.app --env HOME=<home> --env CLAUDE_CONFIG_DIR=<home>/.claude --env CODEX_HOME=<home>/.codex --env REINS_HOME=<home>/.reins --env REINS_TEST=1 --env REINS_AGENTS=1`

What to click:

1. `⌘2` opens Agents. Each card shows its sentence; Codex reads warn in `both`.
2. Each card button of both agents opens its panel; the same button closes it; another one swaps it. Drag the panel's left edge.
3. Claude Code Permissions: type `Bash(make deploy)`, pick Deny, Add; the footer reads "1 unsaved change". Review and save (`⌘S`): the dialog lists the change, the scope and `~/.claude/settings.json`. Save: a toast with Undo. Undo: the rule is gone.
4. Pick Bypass as the default mode: the review carries the warn note.
5. Esc with a draft: the footer asks "Discard 1 change?" with Keep editing and Discard. Switching the scope or the panel asks the same.
6. Error toast: open Claude Code Advanced, change `sonnet` to `opus`, then add a blank line to `<home>/.claude/settings.json` by hand, then Review and save: an error toast names the reason, and the draft stays.
7. Masked and visible: Advanced shows `"DISABLE_TELEMETRY": "1"`, and `EXAMPLE_TOKEN` and `ANTHROPIC_API_KEY` as `••••`. MCP: open `github`; `GITHUB_TOKEN` reads `••••`; Replace takes a new value without showing the old one.
8. Hooks: the two dead hooks carry "script missing"; Remove 2 dead adds both to the draft. Copy to Codex asks first and warns.
9. Rules: Preview renders the headings, list and inline code; the `@rules/style.md` row opens that file with a crumb back.
10. Codex, `profiles`: Permissions shows `project-edit`; change a file rule, add a domain, turn off Enforce domain rules (warn note).
11. Codex, `both`: Permissions shows "Keep one permission model"; pick one, Review and save; the card's value stops reading "2 models".

/goal Build the Reins Agents page per docs/specs/2026-11-05-reins-agents.md and docs/plans/2026-11-05-reins-agents.md: tasks A1 to A10 in order, one commit each, the UI behind REINS_AGENTS=1 after design language v4 V5. Done means scripts/test.sh passes with the AG2 to AG8 tests against TempHome, and the agents shots render in light and dark. Leave A11 (the real-CLI check with the owner) and A12 (eye approval and cut-over) to the owner. Never push or release, and never touch the real ~/.claude or ~/.codex.
