# Core protocol

The contract between the Go core (`spacevibe`) and the SwiftUI shell: how they talk over stdio, which methods exist, the exact JSON each one carries, and the rules that keep stdout, errors and goldens safe. The Swift `CoreClient` decodes these shapes into Codable types, so a change here is a change to both sides. Architecture: [overview.md](overview.md). Decisions: [ledger](../specs/2026-11-07-core-port-and-spacevibe-identity-decisions.md) SV3, SV4, SV12. Execution: [plan](../plans/2026-11-07-go-core-and-spacevibe-identity.md) PR.1 to PR.3.

**Status.** Implemented and wired. The transport is in [`core/internal/rpc`](../../core/internal/rpc) (framing, handshake, errors, strict params, cancellation, drain, size caps). Every method of the table is registered by [`core/internal/rpc/methods`](../../core/internal/rpc/methods), which builds the domain services once and registers them on the registry. The entry point is [`core/cmd/spacevibe`](../../core/cmd/spacevibe) (`rpc`, the one-shot `--json` commands, `--version`, the stdout guard, the startup problem, the write guard). The transcripts and contract cases are in [`core/testdata/rpc`](../../core/testdata/rpc) and `TestContract`. `TestDocMethodTable` fails when the table, `AllMethods` and the registered set (with `initialize`) are not the same list; it also refuses any statusline, capture or `Add*` method. Each shape is tagged by origin:

- no tag: copied from an existing Swift `Codable` type, field for field.
- `(new)`: Swift has no encoding for it (the type is not `Codable`, or the function is new), so the shape is defined here from the Swift fields. Change it only together with its Go test and its Swift DTO.

## Framing and lifecycle

- **NDJSON, JSON-RPC 2.0.** One object per line, UTF-8, no raw newline inside a message. Request lines are capped at 1 MiB and response lines at 64 MiB. Batches (a JSON array) are refused with -32600. Ids are integers or strings, echoed verbatim; a `null`, fractional, exponent or other non-integer id is -32600 with id `null`. A blank line is ignored. A request whose id is still in flight is refused with -32600 (the first keeps running). Params may be absent or `null` (read as `{}`); any other non-object is -32602. Responses may arrive in any order: requests run concurrently, writes serialize on the write lock.
- **Spawn.** The shell starts `Contents/Helpers/spacevibe` with the argv array `["rpc"]` (no shell) and inherits the environment. The binary lives in `Helpers`, not `MacOS`, because `SpaceVibe` and `spacevibe` collide on a case-insensitive volume.
- **Handshake.** The first request must be `initialize`; its params must be an object, but `client` may be missing (a given `client` is `{name, version}`, unknown members are -32602). Any other request before it gets -32002; notifications before it are dropped. A second `initialize` gets -32600. `protocolVersion` is the integer `1`; any other value gets -32001 with `data: {protocolVersion: 1}`. The shell takes the core's name, version, env prefix and data folder from the result and hard-codes only the helper's path (SV12).
- **Startup problem** `(new)`. If the environment is refused (`internal/config`, or the real-home guard under `SPACEVIBE_TEST=1`), `initialize` still succeeds, so the shell learns the identity, and every other registered method fails with -32000, status 500 and the startup sentence. An unknown method is -32601 first, and a request before `initialize` is -32002 first. The sentence is the error text of `config.Load`, `roots.RealHome`, `roots.Resolve` or `proc.New` (an unreadable `SPACEVIBE_PROC_FIXTURE` file, only under `SPACEVIBE_TEST=1`): it may name an environment variable (and the offending `SPACEVIBE_TEST` value) or a root path, never file content. This mirrors `AppEnvironment.startupProblem`: a screen shows the sentence instead of reading anything.
- **Shutdown.** On stdin EOF the core stops reading and cancels the context of every in-flight request. A handler stops on cancel, except one inside the write lock, which ignores the context and finishes its write. The core waits at most 5 s for them, then exits 0. A write that outlives the drain is abandoned at exit. A read error other than EOF exits 1. Every write ends in one atomic rename, so a file is old or new, never half; the rare leftover is a `.spacevibe-*.tmp` file.
- **Size overflow** `(new)`. A request line over the cap is discarded through its newline and answered with -32600 and id `null`; the stream stays usable. A result that would pass 64 MiB is replaced by -32000, status 413, "The result is too large."

## Errors

| Code | Meaning | `data` |
| --- | --- | --- |
| -32700 | Line is not valid UTF-8 JSON. The stream continues. | none |
| -32600 | Not a valid request: batch, oversized line, repeated `initialize`, a `null` or non-integer id, or an id that is still in flight. | none |
| -32601 | Unknown method. | none |
| -32602 | Params are not an object, or have a wrong type or an unknown member. The message names the member, never its value. | none |
| -32603 | A panic inside a handler. Fixed message; the reason goes to stderr only. | none |
| -32000 | The engine refused or failed. The message is a `coreerr` sentence. | `{status, message}` |
| -32001 | `initialize` protocol version mismatch. | `{protocolVersion}` |
| -32002 | Request before `initialize`. | none |
| -32800 | Request cancelled by `$/cancelRequest` `(new)`. The plan names no code; PR.2's `cancel_request` case must assert this one. | none |

**`status` follows HTTP** ([`coreerr`](../../core/internal/coreerr/coreerr.go)): 400 bad input, 403 refused, 404 gone, 409 conflicts with the current state, 413 too large, 500 the write failed. `message` equals the JSON-RPC `message` and is safe to show: it may name a path or a rule, never file content (S-R3). A parse failure of a settings file becomes a fixed sentence; Go's `encoding/json` and TOML errors quote input and must never be forwarded.

**Settings-file paths are scrubbed by the core** `(new)`. Rules messages and `problems` name the absolute settings file (`RulesStore` 409s do). The Go core swaps that path for the scope's label in every `rules.*` message and problem, using `scopeLabel` (the Rules screen does not), because otherwise nothing is left to do it and paths reach the UI. Journal labels for rules writes still contain the project folder (`global` or `project <dir>`) and are shown in the Undo toast; that is existing behavior.

## Notifications and cancellation

Notifications have no `id` and get no response.

| Direction | Name | Params |
| --- | --- | --- |
| core to shell | usage/progress | `{id, done, total}`: `id` is the `usage.scan` request id. Sent after every 20 files and once at the end. |
| core to shell | activity/report | The full `ActivityReport`, see below. |
| shell to core | $/cancelRequest | `{id}`. An unknown or finished id is ignored. |

A cancelled read answers -32800. A write is cancellable only before it takes the write lock; once it has started, the cancel is ignored and the response is the real result, so a cancel never leaves a half-applied change. Cancelling `usage.scan` leaves `usage-cache.json` as it was and the process's usage state unchanged. Neither a write nor `activity.stop` is ever retried by the core, and a handler never holds the write lock itself: the service takes it around its own write, after looking at the cancel once. `loadout.copyToOther`, `loadout.removeItem`, `loadout.removeDeadHooks` and `journal.undo` look again as the first step inside the lock, so one cancelled while it queued changes nothing and answers -32800; the `rules.*` writes still look only once.

## Activity subscription

- **Full snapshot first.** The `activity.subscribe` response is a complete `ActivityReport`. After it the core polls every 3 s while subscribed, and pushes `activity/report` only when the encoded report differs from the last one sent to this connection. The baseline is the very report the response carried (the poll does not take a second snapshot of its own), so a change between the two reads cannot be lost. The first possible push is one interval after the response.
- **Resync, not deltas.** Every notification replaces the shell's whole report. There are no sequence numbers and no partial updates. After a core restart the subscription is gone; the shell re-subscribes and gets a fresh snapshot.
- **"Changed" includes the clock** `(new)`. `ageMs` and `lastWriteAgoMs` are computed from now, so a live session changes the report on every poll and pushes every 3 s; with no live session and no log change the core stays silent. H10 in the plan times this on a real home.
- **One subscription per connection.** A second `activity.subscribe` returns a fresh snapshot and resets the baseline. `activity.unsubscribe` is idempotent and stops the polling; the core reads nothing while unsubscribed. End of input cancels the poll before the 5 s drain (`Call.Session` in `rpc`), so no new report is pushed after it. The poll is the core's own loop over `activity.Service.Read`, not `Service.Watch`: `Watch` takes its own first snapshot as the baseline, so a change between the response and that snapshot would never be pushed. `activity.read` and the poll share one engine, so folded offsets are not repeated.

## Swift client

[`CoreClient`](../../Sources/SpaceVibe/Core/CoreClient.swift) maps `CoreService` to the methods above; [`CoreConnection`](../../Sources/SpaceVibe/Core/CoreConnection.swift) owns the process, the handshake and the restarts; [`CoreSession`](../../Sources/SpaceVibe/Core/CoreSession.swift) is one process with its reader thread. What a maintainer would get wrong:

- **The write lock spans processes.** Two app instances run two cores on one data folder, so [`fsx.WithWriteLock`](../../core/internal/fsx/write-lock.go) also takes `flock(LOCK_EX)` on `<data>/write.lock` at its outermost depth.
- **Read the pipe with `read(2)`.** `FileHandle.read(upToCount:)` waits for the whole count, so a short reply sits unseen and the call hangs.
- **A write is never sent again.** A request in flight when the core dies fails with the fixed "restarted" `CoreError`: the dead core may have applied it. A read in flight is sent once more on the new core. A request that never left (the pipe was already dead) is sent again whatever it is. A method the client does not list as a read counts as a write.
- **Cancel differs by kind.** A cancelled read answers `CancellationError` at once and ignores the late reply. A cancelled write sends `$/cancelRequest` and keeps waiting, because once the core is inside the lock the real result (and its Undo entry) must not be hidden.
- **Restarts are lazy.** The next request, or a live Activity subscription, starts the core again; the delay grows 0.25 s to 5 s while it dies without answering a request. A protocol-version mismatch is a stored startup problem, never a restart loop.
- **Dev switches.** `SPACEVIBE_CORE_BINARY` ([`CoreEnvironment`](../../Sources/SpaceVibe/Core/CoreEnvironment.swift)) is honored only in a DEBUG build or under `SPACEVIBE_TEST=1`. Every screen has cut over (Activity and Stop since S.3, Limits since S.4, Loadout since S.5 and S.6, Rules since S.7), so there is no per-screen routing: all of them use the core through `AppEnvironment.goCore`, and `SPACEVIBE_CORE_SCREENS` no longer exists. Every Undo runs on the core too (`AppEnvironment.performWithUndo`). The core's process list under `SPACEVIBE_TEST=1` is the file `SPACEVIBE_PROC_FIXTURE` names, which `scripts/dev-fixture.sh` exports and the core inherits.
- **Tests stop the core with signals.** The shipped binary has no `debug.slow`, so `SIGSTOP` freezes a request in flight and `SIGKILL` ends it.

## Output discipline and security boundaries

- **stdout carries the protocol and nothing else.** One writer goroutine owns it. On darwin the core duplicates fd 1 for the protocol and points fd 1 itself and `os.Stdout` at stderr (`dup`, `dup2`), so a stray `fmt.Println`, a cgo write or a child process lands in the log, not in the stream. Other OSes only repoint `os.Stdout` at the Go level: a write to fd 1 by anything but Go code still reaches the protocol. The contract case `stray_print_on_stderr` holds this.
- **stderr is the log.** Fixed reasons only, no file content, no request params. The shell forwards it to `os.Logger` at debug level.
- **No listener, no network.** The core opens no socket and `go list -deps ./cmd/spacevibe` shows no `net`, `net/http` or `crypto/tls` (S-R5).
- **No recorded command runs.** The only processes are the fixed `ps`, `lsof` and SIGTERM of Activity, with the pid looked up again from the live system. `activity.stop` takes `{cli, id}` and never a pid (S-R4). `spacevibe statusline capture` is a command-line subcommand with no RPC route; the case `rpc_cannot_capture` holds that.
- **Environment is read in one place**, [`internal/config`](../../core/internal/config/config.go), fail-closed (`SPACEVIBE_TEST` is `1` or `0`, `SPACEVIBE_HOME` is absolute; `HOME`, `CLAUDE_CONFIG_DIR` and `CODEX_HOME` are absolute when set, else the environment is a startup problem with a fixed sentence that names the variable: `initialize` answers and every other method answers 500 with it). Under `SPACEVIBE_TEST=1` a root under the real home, taken from the password database and not `$HOME`, is refused (S-R1). The fixture process adapter exists only under that flag: `SPACEVIBE_PROC_FIXTURE` (`Config.ProcFixture`) names its process-list file, `proc.New` receives the path as an argument, and an unreadable file is an error sentence. Outside `SPACEVIBE_TEST=1` the variable is ignored.
- **The write guard is a startup requirement.** The entry point calls `fsx.InstallWriteGuard(cfg)` right after `config.Load`, in `rpc` and in every one-shot command, before any method can run. Without it the primitives of [`fsx`](../../core/internal/fsx/write-guard.go) write freely and the real-home refusal (S-R1) is void for writes. The case `write_guard_installed` aims a write at the real home through a debug method that exists only in a binary built with `-tags contracttest` and expects the guard's refusal; the shipped binary has no debug method.
- **Params are strict** `(new)`. A misspelled `verdict` must not fall back to a default and write something else, so unknown members are -32602.
- **A project folder must be one project discovery found.** The core keeps one discovered list per process, shared by the inventory and rules services: `inventory.read` and `loadout.rows` refresh it, `rules.snapshot` with `refreshProjects: true` refreshes it, every other `rules.*` call reuses it, and discovery runs once if it is empty. A write or preview for a folder outside the list is 404, so no caller can make the core create `<any folder>/.claude/settings.json`; `rules.snapshot` alone reads such a folder as `global` (see "Behavior the table cannot say").

## One-shot `--json`

`spacevibe inventory|usage|activity|limits|rules --json` prints the same result object as the matching read method (`inventory.read`, `usage.scan`, `activity.read`, `limits.read`, `rules.snapshot`), with the same encoder, so a contract test compares bytes (`one_shot_equals_rpc`; `activity` is compared with its clock-driven members masked, because `ageMs` moves). They add no write path: the one file any of them can write is `usage-cache.json`, as `usage.scan` does, and `usage` sends no progress. `rules` prints the global snapshot; `rules --dir <path>` prints the project snapshot for that folder, with the same fallback as the method (a folder discovery did not find reads as global; a relative one is 400, so exit 1). `--dir` is accepted by `rules` only. Exit codes: 0 success, 1 core error (the safe message on stderr, nothing on stdout; also a refused environment), 2 usage (a missing `--json`, an unknown or misplaced flag). There are no write commands, and no command reaches statusline capture except the collector `spacevibe statusline capture`, which Claude runs.

## Methods

Params and results use the types defined under "Wire types". "Journal entry" is the label pattern and the op kinds recorded; `JournalEntryRef` is what a write returns. Errors list the `data.status` values a caller must handle, besides the generic codes above. Reads touch nothing except where "side effects" says so.

| Method | Params | Result | Errors (status) | Side effects | Journal entry |
| --- | --- | --- | --- | --- | --- |
| `initialize` | `{protocolVersion, client?:{name, version}}` | `{protocolVersion, core:{name, version}, identity:{envPrefix, dataDir}, methods:string[]}` | -32001, -32600 | Starts the session | none |
| `inventory.read` | `{}` | `InventorySnapshot`, no `cells`, hook `usage` null | none: unreadable files become `problems` | Refreshes the discovered-project list | none |
| `usage.scan` | `{}` | `UsageResult`; sends `usage/progress`; stores the result as the process's usage state | 409 a scan is already running; -32800 | Reads logs; writes `<data>/usage-cache.json` | none |
| `loadout.rows` | `{}` | `LoadoutRows`; `problems` are the raw sentences | none | Reads inventory; attaches the stored usage state | none |
| `activity.read` | `{}` | `ActivityReport` | none: the engine reports what it could not read inside the report | none | none |
| `activity.subscribe` | `{}` | `ActivityReport`; later `activity/report` | none | Starts a 3 s poll | none |
| `activity.unsubscribe` | `{}` | `{}` | none | Stops the poll | none |
| `activity.stop` | `{cli, id}` | `{exited:boolean}` | 404 not running; 409 could not be verified (ps, lsof or the sessions folder unreadable, or the start time unknown: nothing is sent); 403 other user; 500 | SIGTERM to the pid found now; waits up to 3 s | none: not undoable, the shell confirms first |
| `loadout.copyToOther` | `{id}` | `{entry:JournalEntryRef}` | 400 a hook Codex cannot take or an event it lacks; 403 a path outside the CLI folder; 404; 409 the name exists in the other CLI, a source that cannot be read or is not a plain file, an agent with no instructions; 413 a skill file over 16 MiB, a skill over 64 MiB, an agent over 1 MiB; 500 | Creates the skill folder, agent file or Claude hook in the other CLI | label `Copied skill\|agent <name> to <CLI>` or `Added <event> hook to Claude Code`; ops `created`, `hook-added` |
| `loadout.removeItem` | `{id}` | `{entry:JournalEntryRef}` | 403 plugin or project item; 404; 409; 500 | Moves the item to the data-folder trash; a link keeps its target text | label `Removed skill\|agent <name> from <CLI>` or `Removed <event> hook from <CLI>`; ops `moved`, `link-removed`, `hook-removed` |
| `loadout.removeDeadHooks` | `{cli}` | `{entry:JournalEntryRef}` | 409 none dead; 500 | One write to the CLI's hook file | label `Removed N dead hooks from <CLI>`; ops `hook-removed` |
| `journal.undo` | `{id}` | `{label:string}` | 404 gone; 409 already undone, or a target changed or exists again; 400 an entry this version cannot undo or a path outside the managed folders; 500 the undo was rolled back or stopped part way | Reverses all ops last first, all or nothing; marks the entry undone | none: the entry is marked `undone` |
| `journal.history` | `{}` | `{entries:JournalEntryRef[]}`, newest first, at most 200 | 409 the journal exists but is not a JSON array of entries (an element without a string `id` counts): it is refused, never read as empty or with elements dropped | none | none |
| `rules.snapshot` | `{scope, dir, refreshProjects?}` | `RulesSnapshot` | 400 relative dir, a global scope with a `dir`, or an unknown scope; an unknown project is not an error (see below) | May refresh the project list | none |
| `rules.preview` | `{scope, dir, capability, verdict}` | `CapabilityPreview` | 400, 404, 409 | none: writes nothing | none |
| `rules.setCapability` | `{scope, dir, capability, verdict}` | `{entry:JournalEntryRef\|null}`; null = the file already holds that | 400, 404, 409, 500 | Edits the scope's `settings.json` in place | label `Set <capability> to <Verdict> (<scope>)`; op `file-edited` |
| `rules.add` | `{scope, dir, verdict, rule}` | `{entry:JournalEntryRef}` | 400 invalid rule; 404; 409 duplicate, not valid JSON, or a linked file | Same | label `Added <verdict> rule <rule> (<scope>)`; op `file-edited` |
| `rules.remove` | `{scope, dir, verdict, rule}` | `{entry:JournalEntryRef}` | 404; 409 the rule already changed | Same | label `Removed <verdict> rule <rule> (<scope>)`; op `file-edited` |
| `rules.changeVerdict` | `{scope, dir, rule, from, to}` | `{entry:JournalEntryRef}` | 400 same verdict; 404; 409 | Same | label `Changed <rule> from <a> to <b> (<scope>)`; op `file-edited` |
| `rules.check` | `{rule}` | `{valid:boolean, message:string\|null}` | none | none | none |
| `limits.read` | `{}` | `{limits:LimitsEntry[]}` in order claude, codex, gemini | none | Reads local files only: no request, no credential, no CLI started | none |

Behavior the table cannot say:

- **`rules.snapshot` and an unknown project.** A `project` or `local` scope whose folder discovery did not find is read as `global`, as the Swift screen does; the result's `scope` and `dir` say what was read, so the shell compares them with what it asked for. A relative `dir` is 400 and a `dir` with the `global` scope is 400. The other `rules.*` methods answer 404 for an unknown project folder, so no call can create `<folder>/.claude/settings.json` anywhere.
- **Unreadable is not empty** `(new)`. A file or folder the core cannot look at (a macOS privacy denial, an unreadable settings file) is reported as unknown, never as no rules or the Codex defaults: `RulesSnapshot.notReadable` and `globalNotReadable` (the scope is not editable), `CodexPermissions.notReadable`, `skippedLines`, `rules.unreadable` and `rules.folderNotReadable`, each with a fixed sentence in `problems` or `warnings` that names the file and never quotes it. The Swift screen has no such state; the shell must show it instead of an empty list. Inventory reports a settings file, skills folder, agents folder, `SKILL.md` or agent file, plugin `hooks.json` or `installed_plugins.json` it could not read as a `problems` line, and an invalid Claude `settings.json` adds one saying that enabled plugins and skill overrides are not known (G-fix.13). Hooks of a type other than `command` (http, mcp_tool, prompt, agent) are not listed; one line, "N hooks of other types are not shown.", counts them over all files (G-fix.14). A Codex `config.toml` or `.rules` file past its read cap adds a `warnings` line ("too large to read completely") instead of passing as complete. The Claude state file has one size cap for the usage cache and the status line account key; past it the Claude limit reads `unreadable`.
- **Other process-wide state.** The inventory and rules services share one discovered-project list: every `inventory.read` and `loadout.rows` hands its list to rules, and `refreshProjects` runs discovery again for both.
- **`usage.scan` owns the usage state.** The core keeps the last `UsageResult` of the process. `loadout.rows` attaches it, or reports `usage: "scanning"` and `pending` cells when no scan has finished in this process. The shell does not send totals back. A core restart forgets the state; `usage-cache.json` makes the next scan fast.
- **`loadout.rows` replaces three Swift calls** `(new)`: `Inventory.read`, `attachUsage` and `filterCounts` (per scope and per row key). Grouping rows by `key`, sorting and labels stay in Swift. Problems come back unshortened, with absolute paths; the shell applies the existing rule that shortens the home folder before showing them.
- **`rules.setCapability` returning null is not an error.** The core reports it; the app turns it into the 409 sentence "Nothing to change: the file already holds that." (`RulesModel.write` does it). `rules.add`, `remove` and `changeVerdict` never return null: the engine throws that 409 itself.
- **`rules.check`** is the live check of a rule's shape (the Rules model calls it before every add), built on `Rules.checkedRule`: empty text, over 1000 UTF-16 units, a newline, or no `Tool` or `Tool(pattern)` shape. `message` is the same sentence the write would refuse with. The write path checks again; this method is advice.
- **Journal ops are not exposed.** `JournalEntryRef` carries `count` only: ops hold absolute paths and trash names, and no Swift caller reads them (`AppEnvironment` uses the id and the label). The journal file is `<data>/journal.json`, newest first, 200 entries, and a journal that exists but is not a JSON array of entries (every element needs a string `id`) makes every write 409; Swift silently dropped an element without an id on the next write.
- **`addSkill` and `addAgent` are not methods.** The app has no caller.
- **The pid is never a parameter.** `activity.stop` finds the live process from the id, so a reused pid cannot be signalled. A Codex id before its first prompt is `pid:<n>:<start-ms>`, bound to the process start; an id ending `:unknown` cannot authorize a stop.

## Wire types

Keys are camelCase exactly as written. A nullable member is always present with `null`; the exceptions are marked "omitted". Timestamps are ISO 8601 UTC with milliseconds (`2026-11-07T10:00:00.000Z`), the same text as a journal `at`; Limits is the one exception, below. Counts and ids are integers.

```ts
type Cli = "claude" | "codex"
type Scope = "global" | "project" | "local"      // rules scope; dir is null for "global", absolute otherwise
type Verdict = "allow" | "ask" | "deny"
type Capability = "read" | "edit" | "run" | "network" | "push" | "secrets"
type CapabilityState = "allow" | "ask" | "deny" | "mixed" | "none"

type JournalEntryRef = { id: string, at: string, label: string, undone: boolean, count: number }
// (new) built from JournalEntry / HistoryItem; ops are left out.
```

Inventory and usage (from `InventoryTypes.swift` and `UsageScanTypes.swift`):

```ts
type Cell =
  | { state: "counted", runs: number, last: string | null, errors?: number }   // errors omitted unless a hook
  | { state: "pending", reason: string }
  | { state: "unmeasurable", reason: string }
  | { state: "missing" }
type Cells = { claude: Cell, codex: Cell }

type InventoryItem = {                            // a skill or a subagent
  id: string, cli: Cli, kind: "skill" | "agent", name: string, entry: string, description: string,
  owner: string,                                  // "user", "link", or a plugin name
  path: string, file: string, removable: boolean, scope: "global" | "project", project: string | null,
  inOther: boolean, key: string,                  // key = "<kind>:<project or empty>:<bare name>"
  override?: string | null,                       // written on every Claude global skill (null when settings hold no value); omitted on all other items
  cells?: Cells                                   // omitted until usage is attached
}
type HookUsage = { runs: number, avgMs: number | null, totalMs: number, errors: number, last: string | null }
type InventoryHook = {
  id: string, cli: Cli, kind: "hook", event: string, matcher: string | null, command: string, timeout: number | null,
  async: boolean, owner: string, removable: boolean, dead: boolean, paths: string[], hash: string, file: string,
  scope: "global" | "project", project: string | null,
  key: string,                                    // "hook:<project or empty>:<hash>"
  cells?: Cells, usage: HookUsage | null          // usage is always present; null when unknown or not logged
}
type InventorySnapshot = {
  items: InventoryItem[], hooks: InventoryHook[], problems: string[],
  events: { claude: string[], codex: string[] }, roots: { claude: string, codex: string }
}

type NameUsage = { sessions: number, days: string[], last: string | null }       // days: YYYY-MM-DD, sorted
type HookTotals = { runs: number, ms: number, timed: number, errors: number, last: string | null }
type CliTotals = { skill: { [name: string]: NameUsage }, agent: { [name: string]: NameUsage }, hook: { [hash: string]: HookTotals } }
type LogWindow = { files: number, oldest: string | null, newest: number | null }  // newest: ms since 1970
type UsageResult = {
  totals: { claude: CliTotals, codex: CliTotals }, sessions: { claude: number, codex: number },
  windows: { claude: LogWindow, codex: LogWindow }, files: number
}

type FilterCounts = { all: number, only: { claude: number, codex: number }, neverRan: number, dead: number }
type LoadoutRows = {                              // (new) assembled from LoadoutData.build and LoadoutRows.build
  usage: "scanning" | "ready",
  items: InventoryItem[], hooks: InventoryHook[],  // cells attached, hook usage attached
  problems: string[], events: { claude: string[], codex: string[] }, roots: { claude: string, codex: string },
  countsByScope: { [scope: string]: FilterCounts },   // key "global", or an absolute project folder
  rowFlags: { [rowKey: string]: { one: boolean, neverRan: boolean, dead: boolean } }
}
// rowFlags[key].one = (only.claude + only.codex > 0) of filterCounts over that row's members; neverRan and dead are counts > 0.
```

Activity (from `ActivityReport.jsonObject`, the same names as the frozen `activity.json`):

```ts
type ActivityReport = {
  sessions: {
    cli: Cli, id: string, title: string, project: string | null, pid: number,
    state: "running" | "waiting" | "idle" | "ended" | "unmeasurable", stateReason: string,
    reasonCode: string | null,                    // open: known values below under unmeasurable
    currentTool: { name: string, target: string } | null,
    ageMs: number | null, lastWriteAgoMs: number | null,
    cost: { usd: number, estimated: true } | null, costNote: string | null
  }[],
  failures: {
    kind: "command" | "hook", cli: Cli, key: string, title: string, count: number, exit: number | null, reason: string,
    projects: string[], sessions: number, first: string | null, last: string | null, laterPass: string | null,
    hook: { hash: string, event: string } | null
  }[],
  files: { path: string, label: string, edits: number, sessions: number, last: string | null, clis: Cli[], projects: string[] }[],
  unmeasurable: { cli: Cli, code: string, text: string }[],     // code: same values as reasonCode
  // known codes: codex-no-rollout, codex-rollout-unreadable (the rollout exists but could not be read), codex-tool-silent, claude-prompt-vs-busy, claude-unknown-status, codex-hook-runs, codex-process-unknown
  stats: { logs: number, truncated: number }
}
```

`reasonCode` and `unmeasurable[].code` are open strings: a Swift DTO must decode an unknown value without failing and show `stateReason` or `text`. `codex-process-unknown` is new in Go: "The system process check failed just now, so Codex sessions cannot be matched to their logs. This is not a log that is missing." It appears on a Codex row, or as one extra `unmeasurable` entry, only while `ps` or `lsof` keeps failing; it is not in the fixed entries.

Rules (the golden's `ruleObject` and preview shapes from `RulesGoldenTests.swift`; the snapshot and Codex shapes are `(new)`):

```ts
type Rule = {                                     // golden ruleObject
  id: string,                                     // "<scope>:<verdict>:<rule>"
  scope: Scope, dir: string | null, file: string, verdict: Verdict, rule: string,
  tool: string | null, specifier: string | null
}
type CapabilityCell = { capability: Capability, label: string, state: CapabilityState, editable: boolean, rules: Rule[] }
type VerdictRule = { verdict: Verdict, rule: string }
type CapabilityPreview = {                        // golden preview outcome
  capability: Capability, verdict: Verdict, scopeLabel: string, current: CapabilityState, resulting: CapabilityState,
  replaces: VerdictRule[], writes: VerdictRule[]
}
type CodexPermissions = {                         // (new) from CodexPermissions; flag lists keep file order, which the UI shows
  present: boolean, model: "legacy" | "profiles" | "both", unrestricted: boolean, warnings: string[],
  approvalPolicy: { mode: string } | { granular: { key: string, value: boolean }[] } | null,
  sandboxMode: string | null,
  sandboxWorkspaceWrite: { networkAccess: boolean | null, writableRoots: string[] } | null,
  defaultPermissions: string | null, approvalsReviewer: string | null,
  profiles: { name: string, filesystemEntries: number, networkEntries: number, networkFlags: { key: string, value: boolean | string | number }[] }[],
  projects: { path: string, trustLevel: string | null }[],
  rules: { files: number, allow: number, prompt: number, forbidden: number, other: number,
           unreadable: number, folderNotReadable: boolean },   // (new) .rules files not counted; rules folder not listable
  notReadable: boolean,                           // (new) config.toml could not be read: every setting above is unknown, not the defaults
  skippedLines: number                            // (new) config.toml lines the reader could not understand; `warnings` says so
}
type RulesSnapshot = {                            // (new) from the old RulesSnapshot / RulesReader.read (the Swift engine's `readRules`, deleted in S.7), minus UI-only fields
  projectDirs: string[],                          // discovered; display names stay a Swift helper
  globalRuleCount: number,
  scope: Scope, dir: string | null,               // the selection actually read; "global" when the asked project is gone
  fileLabel: string, exists: boolean, problems: string[],      // scrubbed
  rules: Rule[], grid: CapabilityCell[], codex: CodexPermissions,
  notReadable: boolean,                           // (new) the scope's file or folder cannot be looked at: rules and grid are unknown, not empty, and not editable
  globalNotReadable: boolean                      // (new) the same for the global file that globalRuleCount counts
}
```

Limits `(new)`. `Limits`, `CLILimits` and `LimitWindow` are not `Codable`, so the shape follows the projection the Swift-recorded [`limits.json`](../../core/testdata/fixtures/golden/limits.json) golden uses (plan G0.1), which the Go test compares against. The two timestamps are seconds since 1970 as numbers (fractions allowed), the one place this protocol does not use ISO text; do not convert them. If G2.5 changes the golden projection it edits this page in the same change.

```ts
// every nullable member (plan, source, at, minutes, scope) is always present, null when unknown
type LimitsEntry = {
  cli: "claude" | "codex" | "gemini",
  state: "measured" | "notRecorded" | "unreadable" | "notMeasurable" | "notInstalled",
  plan: string | null, source: "claudeCache" | "claudeStatusline" | null,
  at: number | null,                              // when the record was taken; set only when measured
  windows: {
    id: string, minutes: number | null, scope: string | null, usedPercent: number,
    resetsAt: number, active: boolean,            // active: false when the CLI marks it as not applying now
    current: boolean                              // resetsAt is after the core's now
  }[]                                             // [] unless measured, never null
}
```

A window with `current: false` has passed its reset: its `usedPercent` no longer describes the window and reads as unknown, never as 0. The core returns it as recorded. `usedPercent` can pass 100. No field carries file content (S-R3).

## Canonical golden writer

Golden tests do not compare wire output. They build a named projection of a Go result and a golden, run both through one writer, and compare bytes. The writer is [`goldentest.Canonical`](../../core/internal/goldentest/canonical.go):

- object keys sorted in UTF-16 code-unit order, as `Array.prototype.sort` does, not Go's byte order;
- numbers printed as JavaScript prints them ([`number.go`](../../core/internal/goldentest/number.go)): shortest round-trip digits, no exponent from 1e-6 up to 1e21; a `json.Number` is parsed and reprinted, so `1.0` becomes `1`;
- 2-space indent, `": "` after a key, `[]` and `{}` for empty containers, one trailing newline;
- no HTML escaping, and U+2028 and U+2029 written raw, as `JSON.stringify` does; invalid UTF-8 written as U+FFFD;
- structs are refused: build a `map[string]any` tree.

Rules around it:

- **Never use it for the wire.** The wire is compact, one line. The RPC and `--json` share one encoder; only tests canonicalize.
- **Never use `encoding/json` output as expected text.** It sorts differently, escapes `<>&` and U+2028, and prints floats its own way.
- **`$HOME` token.** `HomeToken` replaces the fixture root with `$HOME` in keys and values, on both sides, before comparing.
- **Assert the case count.** `AssertCaseCount` fails a golden test that ran zero cases, so an unloaded golden cannot pass.
- **Goldens are frozen.** `SHA256SUMS` covers `golden/*.json`, `manifest.json` and `zst/*`, and `VerifyChecksums` also fails on a file added to a covered folder. A wrong golden is fixed together with its test in one commit (SV5), and its line in `SHA256SUMS` changes in that commit.
- **Leak guard.** `FindLeaks` scans every file under `core/testdata`, and the decompressed `.zst`, for the real home path, user name and temp root (S-R2). It reports file names, never the matched content.
- **On failure, print a unified diff of the canonical text**; on success, log the canonical SHA-256.
