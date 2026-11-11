# Inventory

What is installed for Claude Code and Codex: skills, subagents and hooks, read from disk without running anything, then joined to usage so each row can say whether it ran. The Agents page, the filter counts and the delete and warning actions all read this snapshot. Terms follow [GLOSSARY.md](../../GLOSSARY.md).

## Responsibilities and sources of truth

| Part | Responsibility | Source |
| --- | --- | --- |
| Roots | Where each CLI's config, logs and SpaceVibe's own data live; refuses a real home under `SPACEVIBE_TEST=1` (S-R1) | [roots.go](../../core/internal/roots/roots.go) `Resolve` |
| Read | Walk both CLIs, enabled Claude plugins and discovered projects into one `InventorySnapshot` | [reader.go](../../core/internal/inventory/reader.go) |
| Frontmatter | `name` and `description` of a `SKILL.md` or subagent `.md`; flat `key: value` only, not YAML | [frontmatter.go](../../core/internal/inventory/frontmatter.go) |
| Project discovery | Find projects that have their own `.claude` folder | [projects.go](../../core/internal/inventory/projects.go) |
| Hook identity and dead hooks | Hook hash, script paths named by a command | [hashes.go](../../core/internal/hashes/hashes.go), [script-paths.go](../../core/internal/inventory/script-paths.go) |
| Usage join | Add a usage cell per CLI to every row | [attach-usage.go](../../core/internal/inventory/attach-usage.go) |
| Filter counts | Counts for the filter chips | [filter-counts.go](../../core/internal/inventory/filter-counts.go) |
| Types | Row, cell and snapshot shapes, hook events per CLI | [types.go](../../core/internal/inventory/types.go) |
| File access | Bounded reads that tell "missing" from "cannot be read" | [fileio.go](../../core/internal/inventory/fileio.go) |

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
- **Split rows.** The core's `key` can hold two members of one CLI (a user skill and a plugin skill of one name; two hooks of one hash with different matchers). The core still builds `cells` and `rowFlags` per `key`, last member wins. The shell ([`LoadoutRows.build`](../../Sources/SpaceVibe/Loadout/LoadoutRows.swift)) therefore splits such a group by owner class (`user` and `link` together, else the plugin name; for hooks also the matcher): the first part keeps the core `key`, later parts are `<key>#<n>`, and a duplicate inside one part takes the next number. A split row reads `missing` for a CLI it has no member in, takes `rowFlags` from the core `key`, and a group with at most one member per CLI is unchanged. `globalCount` is the number of built global rows. These initial numbered keys are not stable identities: after a reload, `LoadoutData.build` matches surviving core member ids to the previous rows and reserves their display keys before naming new rows. This keeps the current row, multi-selection and open details on the same surviving member when a sibling is removed or reordered; core usage and flags still use the original core key.
- **Hook hash is event plus command.** Hashing the command alone inflates run counts, because the same command is often wired to several events ([hashes.go](../../core/internal/hashes/hashes.go)). The logs do not say which file a hook came from, so a hook in a global and a project file shares one count.
- **Dead hook.** A hook is dead only when its command names at least one script path and every path is missing. A path SpaceVibe cannot stat is not "missing": the hook is not marked dead and a problem sentence says so.
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
- **Counted**: otherwise, with the run count. For a skill or subagent the count is sessions that used it; for a hook it is runs. A skill is looked up under its name and under its folder name (Codex logs the folder name, which can differ from the frontmatter `name`); the larger session count wins, they are not added, because one session can match both.

"Added" is the first time SpaceVibe saw the row's `id`, kept in `<data>/first-seen.json` (see [first-seen.go](../../core/internal/inventory/first-seen.go)). The pure builders `AttachUsage` and `BuildLoadoutRows` take no store: they read the file's modification time (`SKILL.md`, the subagent file, or the settings file holding the hook, which any edit moves). Only `Service.Rows` (`loadout.rows`) passes the store's times in. This is a heuristic either way (see `pendingReason`).

- **Seeding.** With no store yet, each id is recorded with its file's modification time, so the first run reads as the modification-time rule did. An id that appears after the store exists is recorded as "now", whatever its file's date: a skill unzipped with a 90-day-old date still reads "Added in the last 24 hours".
- **Kept ids.** An id missing from one read stays in the store, so a Remove and its Undo keep the original time. An entry is dropped only when the id has been absent for 90 days. "Last seen" is written again at most once a day, so a read that changes nothing does not write the file.
- **Never fails the read.** A corrupt, oversized, unreadable or newer-version file is left as it is and `loadout.rows` answers from modification times (delete the file to start over). A data folder that cannot be created or written does the same. The write goes through the guarded atomic write, file 0600 in a 0700 folder.

## Verification

- `scripts/test.sh`: `cd core && go test ./...` runs [inventory_test.go](../../core/internal/inventory/inventory_test.go), [frontmatter_test.go](../../core/internal/inventory/frontmatter_test.go) and [roots_test.go](../../core/internal/roots/roots_test.go) against temporary homes or the fixture home, never the real config.
- The goldens are frozen (SV5); the Node core that generated them is deleted and lives in git history.
