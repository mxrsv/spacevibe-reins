# Reins: Agents

Date: 2026-11-05
Status: the owner confirmed the intent on 2026-11-04, through an interview and a grilling in chat. Mock C′ was accepted as "tạm ổn" on 2026-11-05, after the panel fixes. The page takes the v4 look of the [design-language spec](2026-11-03-reins-design-language.md), picked the same day.
Parent spec: [Reins](2026-11-02-reins.md). This page replaces its Rules tab and moves hooks out of Loadout.
Execution: [plan](../plans/2026-11-05-reins-agents.md), after [design language v4](../plans/2026-11-05-reins-design-language-v4.md).
Mocks, tracked in [`mocks/agents/`](../../mocks/agents/index.html) with synthetic data (serve the folder, for example `python3 -m http.server 4186 --directory mocks/agents`):
- [`agents-panel.html`](../../mocks/agents/agents-panel.html): C′, also option C′ of that folder's `index.html`.
- [`controls.html`](../../mocks/agents/controls.html)`?icons=tabler&buttons=a`: the v4 look applied to C′.

## Intent

- **Outcome:** one page with a card per agent. Each card has buttons that open that agent's configuration in a panel on the right, where every setting of Claude Code and Codex can be changed. The owner asked for "toàn diện, không hạn chế".
- **User:** the owner, the only user today, who judges the interface by eye.
- **Why:** each agent's configuration is spread over Rules and Loadout. The owner wants one place per agent, in that CLI's own terms.
- **Success:**
  - From the page, a permission is changed in at most two clicks plus the edit, saved after one confirmation, and undone from the toast.
  - The window is blocked only while that confirmation is open.
  - The build matches the mock by the owner's eye.
- **Constraint:**
  - Claude Code and Codex only for now; the layout leaves room for a third agent.
  - Every write keeps a restorable copy.
  - Secrets are never shown.
  - Screens compose components and tokens only.
- **Out of scope:** listed at the end.

## Interface

- **Placement.** Agents replaces Rules in the sidebar: Loadout, Agents, Activity, then the Limits entry, with Agents on `⌘2`. Its sidebar icon is Solar's `bot`.
- **Page.** One card per agent, stacked, with no tools row.
  - The card opens with the 40 pt CLI mark, the name in `title`, and one sentence at Global:
    - Claude Code: its default mode, then the ask and deny rule counts.
    - Codex: the sentence on how it runs, in the warn tone when it has no sandbox or never asks.
  - The config root (`~/.claude`, `~/.codex`) sits on the right.
  - Below come the card buttons, each a v4 card button:

    | Button | Value shown |
    | --- | --- |
    | Rules | the file name |
    | Permissions | Claude: the rule count; Codex: the sandbox |
    | Hooks | the count, with "N dead" in danger |
    | MCP | the count |
    | Model | the model name, or "default" |
    | Advanced | none; the same button as a ghost |
- **Panel.** A right-hand inspector that pushes the content aside. It is not a modal and not an overlay (owner, 2026-11-04 and 2026-11-05).
  - Only one panel is open at a time.
  - Clicking the open panel's button again closes it; clicking another button swaps the panel, behind the draft guard.
  - **Width:** drag the left edge between 420 and 720 pt. The width is remembered separately for Advanced and for the other panels, and Advanced opens at 720.
  - The agent cards never get narrower than 440 pt; the window's minimum width grows instead.
  - **Header:** the small CLI mark, the panel's name, the agent's name and Close (`Esc`).
  - **Tools row:** the panel's scope picker, the file path and Show in Finder. In Rules it is Edit | Preview and Open in editor instead.
- **Scope.** Each panel has its own picker. It starts at Global and remembers the agent's last choice until the app quits. Projects come from the inventory's project list.

  | Panel | Claude Code | Codex |
  | --- | --- | --- |
  | Rules | Global `~/.claude/CLAUDE.md`, Project `<p>/CLAUDE.md`, Local `<p>/CLAUDE.local.md` | Global `~/.codex/AGENTS.md`, Project `<p>/AGENTS.md` |
  | Permissions, Hooks, Model, Advanced | Global `~/.claude/settings.json`, Project `<p>/.claude/settings.json`, Local `<p>/.claude/settings.local.json` | Global `~/.codex/config.toml`, plus `~/.codex/rules/*.rules` for command rules and `~/.codex/hooks.json` for hooks. Per project, only the trust level |
  | MCP | User `~/.claude.json`, Project `<p>/.mcp.json`, Local: that project's entry in `~/.claude.json` | Global, `[mcp_servers]` in `~/.codex/config.toml` |
- **Draft and save.**
  - Edits stay in the panel as a draft. The footer shows "N unsaved changes", Discard, and Review and save (`⌘S`).
  - Review opens the `ConfirmationDialog`. It lists each change (Add, Remove, Change, Replace, Edit, with verdict tags), the scope, the file or files, and "Reins keeps a copy you can restore".
  - Bypass, `danger-full-access` and `never` each add a warn note that says the consequence.
  - Saving writes the files, closes the dialog and shows a toast with Undo.
  - A save that fails shows an error toast that names the reason, and the panel keeps the draft so nothing typed is lost (owner, 2026-11-05). The reasons include a refused `~/.claude.json`, a file that changed shape, a guard, a write error and a missing permission.
  - `Esc`, Close, or switching the panel or scope while a draft exists turns the footer into "Discard N changes?" with Keep editing and Discard. No second dialog opens.
- **Rules (both CLIs).**
  - The file opens in a Markdown editor with Edit and Preview.
  - Preview renders headings, lists, paragraphs, inline code and bold.
  - A line `@path` is a row that opens that file in the same panel, with a crumb back.
  - An empty file shows an empty state that starts editing.
- **Permissions, Claude Code.**
  - **Default mode:** a menu with Ask first, Accept edits, Plan and Bypass, plus "Same as Global (value)" at Project and Local. A one-line description sits under it, and Bypass is in the warn tone.
  - **Rules card:**
    - An add row: the pattern on its own line, then an Allow | Ask | Deny verdict picker and Add (`↵`).
    - Allow, Ask and Deny groups, each hidden while empty.
    - A rule's verdict tag opens a menu to move it or remove it, and a trash button shows on hover.
    - A pattern must be `Tool` or `Tool(pattern)`. A duplicate is refused, naming the group that already holds it.
  - **Extra folders:** the `additionalDirectories` list, with an add field.
- **Permissions, Codex, at Global.**
  - The status sentence, recomputed from the draft.
  - **How Codex runs:**
    - `approval_policy`: Unless allowed, When needed or Never.
    - `sandbox_mode`: Read only, Workspace or Full access.
    - With Workspace only: the `network_access` switch and the `writable_roots` list.
  - **Command rules:** each `prefix_rule` shows its pattern, with a decision tag menu (Allow, Prompt, Forbidden), an add row and remove.
  - **`default_permissions` profiles:** when Codex uses profiles, the panel edits the active profile instead of `sandbox_mode`. The schema is the one at https://learn.chatgpt.com/docs/permissions.md, read 2026-11-05.
    - **Profile picker:** lists your named profiles and the built-ins `:read-only`, `:workspace` and `:danger-full-access`, the last one warn. A built-in is described but cannot be edited.
    - **A named profile** shows:
      - Based on (`extends`);
      - Files: each `filesystem` entry with Read, Write or Deny, where `:workspace_roots` reads "Workspace roots" and `:tmpdir` reads "Temp folder", plus an add row;
      - Network: `network.enabled`, Enforce domain rules (`features.network_proxy`), and `network.domains` with Allow or Deny.
    - Turning off domain enforcement while the network is on adds a warn note: the network becomes open to every domain.
    - `workspace_roots`, `unix_sockets`, `glob_scan_max_depth` and the proxy settings are edited in Advanced.
    - **When both models are set,** a card offers two choices. "Keep sandbox_mode", which is what Codex uses now, removes `default_permissions`. "Keep the profile" removes `sandbox_mode` and `[sandbox_workspace_write]`.
    - Mock: `agents-panel.html#open=codex/permissions&codex=profiles`, and `&codex=both`.
  - At a project: Trust (Not set, Trusted, Untrusted) and a note that everything else comes from Global.
- **Hooks.**
  - Each row shows the event and matcher, the command, and its runs.
    - Claude Code counts runs from its logs and shows errors as a warn tag.
    - Codex reads "not measurable" with the reason.
    - A dead hook carries a "script missing" danger tag.
  - The card offers Remove N dead, and Add hook (an event menu of that CLI's events, a matcher and a command).
  - Each row has Copy to <other CLI> and remove on hover. A copy is its own confirmed write with a toast. It warns that the other CLI names its tools differently, or that it has no such event.
  - Reins writes hooks and never runs them.
- **MCP.**
  - Each server shows its name, its kind (command or URL) and its target.
  - A plugin-owned server is read-only and carries a lock tag.
  - A row expands to its secrets: the key names, with every value hidden and each one replaceable.
  - Add server takes a name, Command | URL and the target; a server can be removed.
- **Model.**
  - A free-text field. At a project where it is unset, the placeholder reads "Same as Global (x)".
  - Chips list the models seen in the logs, with session counts.
  - Codex also has `model_reasoning_effort`: Minimal, Low, Medium or High.
- **Advanced.**
  - The whole settings file in a code editor with line numbers: Claude's `settings.json` at the chosen scope, or Codex's `config.toml`.
  - The editor checks JSON or TOML syntax only. Any key is allowed, and Save is blocked while the file is invalid, naming the line.
  - Codex `[profiles.*]` are edited here only.
  - `~/.claude.json` never opens here.
- **Loadout.**
  - It keeps Skills and Subagents as rows × CLI columns, so a skill applies to several agents.
  - Its Hooks card, the hook part of the Dead filter, and Remove dead hooks move to the Hooks panel.
- **Hint bar.** With the panel closed: `⌘K`, `Tab` Next button, `Return` Open. With it open: `Esc` Close panel, plus `⌘S` Review and save while a draft exists.

## Writes

- **Locations.** This amends `PRODUCT.md` and the parent spec, Constraints:
  - `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md` and the files they import;
  - Claude's `settings.json` at all three scopes;
  - in `~/.claude.json`, only the user-level `mcpServers` and the per-project `mcpServers`;
  - `<p>/.mcp.json`;
  - `~/.codex/config.toml`, `~/.codex/rules/*.rules` and `~/.codex/hooks.json`.

  Skills and subagents stay where Loadout writes them.
- **Every save:**
  - is one journal entry with a `file-edited` op per file;
  - replaces each file atomically;
  - keeps a restorable copy;
  - is undone from the toast.
- **Only what changed:**
  - JSON goes through `OrderedJSON`, which keeps every other byte.
  - TOML goes through a line-level editor that keeps comments, order and untouched keys. The result is read back with `TOMLReader` before the rename.
- **`~/.claude.json`.** Only `mcpServers` keys are read into the app.
  - Before the rename, Reins checks the file is unchanged since it was read (size, modification time, hash).
  - If it changed, Reins reads it again and applies the same edit to the new content.
  - If that fails, Reins refuses with "Claude Code just changed ~/.claude.json. Nothing was saved; try again."
- **Secrets** (AGENTS.md S-R3 stays).
  - **Never shown or logged:**
    - every value of an MCP server's environment and headers: MCP `env` and `headers` in Claude Code, and in Codex `mcp_servers.*.env`, `http_headers` and `env_http_headers`;
    - elsewhere, any string value whose key name contains `key`, `token`, `secret`, `password` or `auth`, in any case. This covers Claude's `env` and Codex `shell_environment_policy.set`.
  - Any other value shows as it is. For example, `DISABLE_TELEMETRY` in Claude's `env` reads `1`. The owner picked this rule on 2026-11-05, accepting that a secret stored under a name with none of those words would show.
  - **Shown as `••••`.** Replace writes a new value without the old one ever reaching the UI.
  - **In Advanced:** a masked value saved unchanged keeps its original bytes, and a masked value moved to another key is refused.
  - **Restorable copies** keep the secrets, with mode 0600.
  - **Command patterns are shown.** S-R3 covers values, not commands (owner, 2026-11-04).
- **Read-only:**
  - items owned by a plugin;
  - managed settings (organisation policy files), which are shown but never written;
  - a `.rules` file Reins cannot parse into `prefix_rule` calls, which shows the reason.
- **Codex permission models.** A Reins write never leaves both `sandbox_mode` and `default_permissions` set.
- **Applying changes.** No CLI is run to apply a change: Reins edits files.

## Decisions

From the 2026-11-04 interview unless dated otherwise.

- **Panel, not modal.** A modal cramps long content, stacks a second dialog on top and locks the window.
- **Push, not overlay** (2026-11-05). An overlay would cover the cards' buttons and the other agent.
- **Hooks are per agent; skills and subagents are shared.**
- **Codex becomes writable.** This reverses the parent spec's "writing Codex settings is out of scope".
- **Configuration is comprehensive.** Common groups get forms; everything else goes through Advanced.
- **The write boundary in `PRODUCT.md` widens** to every configuration and instruction file of both CLIs.
- **Codex profiles are editable** (Q8-b); Codex `[profiles.*]` stay in Advanced only (Q22-a).
- **Advanced checks syntax only;** there is no bundled schema.

## Out of scope

- A third agent: Gemini CLI, Cursor, OpenCode and others.
- A modal or overlay panel, or two panels at once.
- A bundled settings schema.
- Editing `~/.claude.json` outside MCP.
- Running a CLI command to apply a change.
- Codex `[profiles.*]` outside Advanced.
- Translation.

## Acceptance criteria

- **AG1.** Agents sits at `⌘2` behind a development-only switch until cut-over. At cut-over the switch, the Rules tab and its code, and Loadout's hooks are removed in the same change.
- **AG2.** Each panel and scope has a test against a temporary home:
  - a save writes exactly the edit, and its byte diff stays inside the edited region;
  - Undo restores the original bytes;
  - a second edit in the same save lands in the same journal entry.
- **AG3.** A fixture has MCP `env` and `headers` values, token-like keys in Claude's `env` and Codex's config, and a plain `DISABLE_TELEMETRY`:
  - no masked value appears in any panel, shot, log line or error, while `DISABLE_TELEMETRY` shows its value;
  - Replace writes the new value;
  - an Advanced save that leaves the masked values alone leaves those bytes identical.
- **AG4.** A test changes `~/.claude.json` between Reins reading it and writing it. The edit is applied to the new content or refused with the message, and no other key changes.
- **AG5.** Golden tests edit `config.toml` with comments, dotted keys, inline tables, multi-line arrays and quoted table names:
  - untouched lines stay byte-identical;
  - the result reads back with `TOMLReader`.
- **AG6.** A Reins write never leaves Codex with both permission models set. Each risky value shows its warn note in the confirmation.
- **AG7.** The draft guard behaves as described for `Esc`, Close, switching the panel and switching the scope. Each failure reason named under Draft and save shows its error toast and keeps the draft.
- **AG8.** Only one panel opens at a time; it pushes the content, its width stays within 420 to 720 pt and is remembered, and the cards never go below 440 pt.
- **AG9.** On a throwaway home, a real `claude` and a real `codex` load a permission, a hook, an MCP server, a model and an instruction-file change written by Reins. This extends the parent spec's AC2.
- **AG10.** Shots of the page and of every panel, in both appearances, match mock C′ in the v4 look by the owner's eye, after the last task. Departures are named in the plan.
