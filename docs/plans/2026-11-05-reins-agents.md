# Reins: Agents

Spec: [2026-11-05-reins-agents.md](../specs/2026-11-05-reins-agents.md), AG1 to AG10.
Depends on [design language v4](2026-11-05-reins-design-language-v4.md) V5 (the components) before any UI task here. The core tasks A1 to A6 can start now.
Mock: [`mocks/agents/agents-panel.html`](../../mocks/agents/agents-panel.html) (C′), with the v4 look at [`mocks/agents/controls.html`](../../mocks/agents/controls.html)`?icons=tabler&buttons=a`. Both are tracked with synthetic data, and A12 deletes the folder.
Checkout: `spacevibe-reins` on `main`, shared with other sessions. Commit with `git commit -- <paths>` only.
Started 2026-11-05. Status: the owner approved the write approach below on 2026-11-05 (W9, "ok"), adding that every failure shows a toast. The owner also picked the name-based secret rule the same day. A1 waits only for the A0b mock pick, which with the cut-over is the only owner stop.

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
- [ ] A0b. Before any code, read Codex's `default_permissions` schema from its source or docs (parent spec, "To verify"). Then add the profile editor and the both-models state to mock C′, and the owner picks them together with the W9 approval (AG6).
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
- [ ] A8. The Agents screen behind `REINS_AGENTS=1`, in debug builds only, while Rules stays the default:
  - the cards and panel routing;
  - per-panel scopes remembered per agent;
  - drafts, the review dialog, and the toast with Undo;
  - the Claude Code panels (AG1, AG2, AG7).
- [ ] A9. The Codex panels, including the profile editor and the both-models state picked in A0b (AG6).
- [ ] A10. Shots: `REINS_SHOT_SCREEN=agents` for every panel, both appearances, with drafts, confirmations and errors. Extend `StyleBoundaryTests` to cover `Agents/`.
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

2026-11-05: the plan is written, and the owner approved the write approach and the secret rule. Next: A0b, then A1. Every failed save maps to an error toast in A8 and A9 (AG7).

/goal Build the Reins Agents page per docs/specs/2026-11-05-reins-agents.md and docs/plans/2026-11-05-reins-agents.md: tasks A1 to A10 in order, one commit each, the UI behind REINS_AGENTS=1 after design language v4 V5. Done means scripts/test.sh passes with the AG2 to AG8 tests against TempHome, and the agents shots render in light and dark. Leave A11 (the real-CLI check with the owner) and A12 (eye approval and cut-over) to the owner. Never push or release, and never touch the real ~/.claude or ~/.codex.
