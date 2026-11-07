# SpaceVibe

SpaceVibe is a local macOS app that shows what Claude Code and Codex are equipped with, what they are allowed to do, and what they did. Terms below follow decisions D39, D43 and D46 in the [identity decisions](docs/specs/2026-11-06-reins-linear-identity-decisions.md).

## Language

### Parts of the app

**Core**:
The Go engine in `core/` (binary `spacevibe`). Reads the CLIs' files, counts usage, watches sessions and makes every write. Names the engine only, never the whole app.
_Avoid_: backend, helper, engine (in labels and docs), daemon

**Shell**:
The SwiftUI app in `Sources/SpaceVibe`. Draws what the core reports and asks it for changes; holds no engine logic.
_Avoid_: frontend, client (the shell's `CoreClient` is one class inside it)

### Tools and pages

**CLI**:
Claude Code or Codex (Gemini CLI only where it is shown). Never called an agent.
_Avoid_: agent, tool, provider

**Agents**:
The name of the page that holds Skills, Subagents, Hooks and Rules. Names the page only, never an item.
_Avoid_: Loadout (old page name), using "agent" for a CLI or a subagent

### Items

**Skill**:
A reusable instruction bundle a CLI can invoke.
_Avoid_: item, plugin

**Subagent**:
A delegated worker a CLI can spawn, defined by its own file.
_Avoid_: agent

**Hook**:
A command a CLI runs on a lifecycle event. SpaceVibe shows and writes hooks, never runs them.
_Avoid_: trigger, script

**Rule**:
One permission entry (allow, ask or deny) in a CLI's settings.
_Avoid_: policy, permission (for the entry itself)

**Instructions**:
`CLAUDE.md` and `AGENTS.md` files.
_Avoid_: rules, prompt

**Scope**:
Whether an item is global (user-wide) or belongs to one project.
_Avoid_: level, location

### Usage

**Ran**:
An item that appears in the scanned local logs at least once, with its count.

**Never ran**:
An item that appears in no scanned log. A state to act on. A newly added item carries a quiet note ("added 2 hours ago") so a fresh install is not removed by mistake; there is no separate state for it (D63).
_Avoid_: unused, dead, pending, not counted yet (in labels)

**Unmeasurable**:
SpaceVibe cannot know it from what the CLI or model provides: Codex hooks, a session whose state is unreadable, a model with no price. Never shown as 0 or guessed.

**Missing**:
Not installed in that CLI. About installation, not usage.
_Avoid_: absent, not found

**Runs**:
How many times a hook fired. Used for hooks only.
_Avoid_: uses, executions

**Sessions**:
How many CLI sessions used a skill or subagent. One session counts once however often it was used.
_Avoid_: runs (for skills and subagents)

**Estimated cost**:
Tokens priced at API-equivalent rates, not what a subscription charges. Always labelled as an estimate; a model with no price is unmeasurable.
_Avoid_: spend, bill

**Window**:
One usage-limit period of a subscription (for example 5-hour or weekly), shown as percentage left.
_Avoid_: quota, session (a session is a CLI run)

### Activity

**Session**:
One run of a CLI, from start to end. Activity lists the running ones; `Sessions` counts the ones that used an item.
_Avoid_: conversation, process (a process is what Stop signals)

**Session state**:
Running, waiting (for approval), idle, ended or unmeasurable. Waiting and a long tool run can look the same in a CLI's log, which is why a state can be unmeasurable.
_Avoid_: status

**Stop**:
Ends a running session by signalling its process after the pid is re-checked. The one write with no Undo; it names the pid and the consequence first.
_Avoid_: kill, terminate (in labels)

### Changes

**Journal**:
SpaceVibe's record of every write to a CLI's configuration, holding the old bytes as a restorable copy so the write can be undone.
_Avoid_: history, log (a log is what a CLI writes)

**Undo**:
Restores what one Journal entry replaced. Offered from the toast after a write.
_Avoid_: rollback, revert
