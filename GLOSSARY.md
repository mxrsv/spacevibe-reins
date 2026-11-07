# Reins

Reins is a local macOS app that shows what Claude Code and Codex are equipped with, what they are allowed to do, and what they did. Terms below follow decisions D39, D43 and D46 in the [identity decisions](docs/specs/2026-11-06-reins-linear-identity-decisions.md).

## Language

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
A command a CLI runs on a lifecycle event. Reins shows and writes hooks, never runs them.
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
The CLI keeps no log for this kind of item (Codex hooks). A property of the kind and CLI, never shown as 0.

**Missing**:
Not installed in that CLI. About installation, not usage.
_Avoid_: absent, not found

**Window**:
One usage-limit period of a subscription (for example 5-hour or weekly), shown as percentage left.
_Avoid_: quota, session (a session is a CLI run)
