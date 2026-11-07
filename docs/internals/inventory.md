# Inventory

What is installed for Claude Code and Codex: skills, subagents and hooks, read from disk without running anything, then joined to usage so each row can say whether it ran. The Agents page, the filter counts and the delete and warning actions all read this snapshot. Terms follow [GLOSSARY.md](../../GLOSSARY.md).

## Responsibilities and sources of truth

| Part | Responsibility | Source |
| --- | --- | --- |
| Roots | Where each CLI's config, logs and Reins's own data live; refuses a real home under `SPACEVIBE_TEST=1` (S-R1) | [Roots.swift](../../Sources/ReinsCore/Roots.swift) `Roots.resolve` |
| Read | Walk both CLIs, enabled Claude plugins and discovered projects into one `InventorySnapshot` | [InventoryReader.swift](../../Sources/ReinsCore/InventoryReader.swift) `Inventory.read` |
| Frontmatter | `name` and `description` of a `SKILL.md` or subagent `.md`; flat `key: value` only, not YAML | [Frontmatter.swift](../../Sources/ReinsCore/Frontmatter.swift) |
| Project discovery | Find projects that have their own `.claude` folder | [InventoryProjects.swift](../../Sources/ReinsCore/InventoryProjects.swift) `discoverProjects` |
| Hook identity and dead hooks | Hook hash, script paths named by a command | [InventoryHash.swift](../../Sources/ReinsCore/InventoryHash.swift), [InventoryScriptPaths.swift](../../Sources/ReinsCore/InventoryScriptPaths.swift) |
| Usage join | Add a usage cell per CLI to every row | [InventoryUsageAttach.swift](../../Sources/ReinsCore/InventoryUsageAttach.swift) `attachUsage` |
| Filter counts | Counts for the filter chips | [InventoryFilterCounts.swift](../../Sources/ReinsCore/InventoryFilterCounts.swift) `filterCounts` |
| Types | Row, cell and snapshot shapes, hook events per CLI | [InventoryTypes.swift](../../Sources/ReinsCore/InventoryTypes.swift) |
| File access | Bounded reads that tell "missing" from "cannot be read" | [InventoryFileIO.swift](../../Sources/ReinsCore/InventoryFileIO.swift) |

## Where each fact comes from

| Fact | Read from |
| --- | --- |
| Skills | `<cli root>/skills/<name>/SKILL.md`; plugin skills under the plugin's install folder |
| Subagents | `<cli root>/agents/*.md` (Claude) and `*.toml` (Codex; `name` and `description` only) |
| Hooks | Claude `settings.json`, Codex `hooks.json`, a plugin's `hooks/hooks.json`, a project's `settings.json` and `settings.local.json` |
| Plugins | `plugins/installed_plugins.json` joined to `enabledPlugins` in `settings.json`; a plugin whose install folder is gone is skipped |
| Projects | The `cwd` in the head of the newest Claude session logs, and `[projects."<path>"]` in Codex `config.toml` |
| Skill override | `skillOverrides` in Claude `settings.json`, global skills only |

Settings are read only for hooks, plugin flags and skill overrides. No other value, `env` in particular, is kept or returned (S-R3).

## Runtime path

1. `Roots.resolve` fixes the folders from `HOME`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `SPACEVIBE_HOME`.
2. `Inventory.read` lists each CLI, then enabled plugins, then each discovered project. It reads the disk synchronously; call it off the main thread.
3. `attachUsage` takes a `UsageInput` from the usage scan (`UsageScanner`) and fills `cells` on every row and `usage` on every Claude hook.
4. `filterCounts` turns rows into chip counts.

## Rules that are easy to get wrong

- **Row identity.** An item's `key` is kind, project and bare name, so the same skill in both CLIs is one matrix row. A hook's `key` is project and hash. Its `id` differs: a global hook id hashes owner, event, matcher and command; a project hook id also hashes its file, so the same hook in two files has two ids but one `key`.
- **Hook hash is event plus command.** Hashing the command alone inflates run counts, because the same command is often wired to several events ([InventoryHash.swift](../../Sources/ReinsCore/InventoryHash.swift) `hookHash`). The logs do not say which file a hook came from, so a hook in a global and a project file shares one count.
- **Dead hook.** A hook is dead only when its command names at least one script path and every path is missing. A path Reins cannot stat is not "missing": the hook is not marked dead and a problem sentence says so.
- **Plugin names.** A plugin-qualified name (`plugin:skill`) is matched by its part after the last `:` (`Inventory.bare`).
- **Project discovery is bounded.** At most `Inventory.maxProjects` folders, newest first, 3 logs per folder, 64 KB per log. A project never opened with either CLI is not found, and a `cwd` that falls outside the first 64 KB is missed. The home folder and paths under `.claude/worktrees/` are skipped.
- **Unreadable is not empty.** An unreadable CLI root, folder or settings file adds a sentence to `problems` and keeps going; it never reads as "nothing installed". The UI shows `problems`.
- **Item ownership.** `owner` is `user`, `link` (a symlink) or the plugin name. Only user-level items outside any project are `removable`; plugin items are read-only.
- **Hook events.** `Inventory.events` lists the events each CLI documents. Claude's list comes from its docs, Codex's from observation only.

## Usage cell states

`attachUsage` gives each row one `UsageCellState` per CLI: counted, pending, unmeasurable or missing. [D63](../specs/2026-11-06-reins-linear-identity-decisions.md) replaces `pending` with a note on `Never ran`; the code still emits `pending` until that change lands.

- **Missing**: the row is not installed in that CLI.
- **Unmeasurable**: a Codex hook; Codex logs no hook runs.
- **Pending**: zero runs and no scanned log can have covered the row: its CLI has no scanned logs, its file changed in the last 24 hours, or it changed after the newest log. The scan not having finished also yields pending.
- **Counted**: otherwise, with the run count. For a skill or subagent the count is sessions that used it; for a hook it is runs.

"Installed at" is the file's modification time: `SKILL.md`, the subagent file, or the settings file holding the hook. This is a heuristic, so any edit moves it (see `pendingReason`).

## Verification

- `scripts/test.sh`: [InventoryTests.swift](../../Tests/ReinsCoreTests/InventoryTests.swift), [FrontmatterTests.swift](../../Tests/ReinsCoreTests/FrontmatterTests.swift) and [RootsTests.swift](../../Tests/ReinsCoreTests/RootsTests.swift) run against `TempHome` or the fixture home, never the real config.
- The goldens are frozen (SV5); the Node core that generated them is deleted and lives in git history.
