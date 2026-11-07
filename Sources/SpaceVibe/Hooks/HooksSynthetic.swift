import Foundation

/// Hook rows made in memory for the Hooks shots: states the fixture home cannot hold (a hook only Codex has, a plugin's, a hook
/// on an event only one CLI has, sixty hooks). They are built through `LoadoutRows.build` as the app builds the real rows, and
/// carry the cells the core would attach: a Claude Code hook counts runs, a Codex hook is `Unmeasurable`. Synthetic names only.
enum HooksSynthetic {
    struct Spec {
        let name: String
        let event: String
        var matcher: String?
        let clis: [CoreCLI]
        var runs = 0
        var dead = false
        var plugin: String?
    }

    private static let scripts = "/Users/demo/.claude/scripts"

    /// Shared, Claude Code-only and Codex-only events; a hook only Codex has, on a shared event and on its own; a plugin's hook;
    /// two whose script is gone.
    static let sample: [Spec] = [
        Spec(name: "guard-bash", event: "PreToolUse", matcher: "Bash", clis: [.claude], runs: 412),
        Spec(name: "ci-guard", event: "PreToolUse", matcher: "Bash", clis: [.claude], runs: 9, plugin: "neon"),
        Spec(name: "load-context", event: "SessionStart", clis: [.claude, .codex], runs: 58),
        Spec(name: "format-on-save", event: "PostToolUse", matcher: "Edit|Write", clis: [.claude, .codex], runs: 212),
        Spec(name: "lint-changed", event: "PostToolUse", matcher: "Edit|Write", clis: [.claude, .codex], runs: 96),
        Spec(name: "typecheck-edit", event: "PostToolUse", matcher: "Edit", clis: [.claude], dead: true),
        Spec(name: "track-edits", event: "PostToolUse", matcher: "Edit", clis: [.claude]),
        Spec(name: "auto-allow-read", event: "PermissionRequest", matcher: "Read", clis: [.codex]),
        Spec(name: "track-subagents", event: "SubagentStart", clis: [.codex]),
        Spec(name: "subagent-log", event: "SubagentStop", clis: [.claude, .codex], runs: 22),
        Spec(name: "notify-on-stop", event: "Stop", clis: [.claude, .codex], runs: 58),
        Spec(name: "stop-summary", event: "Stop", clis: [.claude], runs: 31),
        Spec(name: "save-transcript", event: "SessionEnd", clis: [.claude], runs: 40),
        Spec(name: "cleanup-old", event: "SessionEnd", clis: [.claude], dead: true),
        Spec(name: "notify", event: "Notification", clis: [.claude], runs: 77),
        Spec(name: "log-failures", event: "PostToolUseFailure", clis: [.claude], runs: 18),
        Spec(name: "stop-sound", event: "Interrupt", clis: [.codex]),
    ]

    /// Sixty hooks on two shared events, every third in both CLIs.
    static let many: [Spec] = (1 ... 60).map { index in
        Spec(name: "synthetic-\(String(format: "%02d", index))", event: index % 2 == 0 ? "PostToolUse" : "PreToolUse", matcher: "Bash",
             clis: index % 3 == 0 ? [.claude, .codex] : [.claude], runs: index * 3)
    }

    static func rows(_ specs: [Spec], events: [String: [String]]) -> [LoadoutRow] {
        var hooks: [CoreInventoryHook] = []
        var flags: [String: CoreRowFlags] = [:]
        for spec in specs {
            let key = "hook::\(spec.event)-\(spec.name)"
            let cells = CoreCells(
                claude: spec.clis.contains(.claude) ? .counted(runs: spec.runs, last: spec.runs > 0 ? "2026-11-05" : nil, errors: 0) : .missing,
                codex: spec.clis.contains(.codex) ? .unmeasurable(reason: "Codex does not log hook runs") : .missing)
            flags[key] = CoreRowFlags(one: spec.clis.count == 1, neverRan: false, dead: spec.dead)
            for cli in spec.clis {
                let command = "sh '\(scripts)/\(spec.name).sh'"
                hooks.append(CoreInventoryHook(
                    id: "\(cli.rawValue):\(key)", cli: cli, kind: .hook, event: spec.event, matcher: spec.matcher, command: command, timeout: nil,
                    async: false, owner: spec.plugin ?? "user", removable: spec.plugin == nil, dead: spec.dead, paths: ["\(scripts)/\(spec.name).sh"],
                    hash: "\(spec.event)-\(spec.name)", file: "/Users/demo/.\(cli.rawValue)/settings.json", scope: .global, project: nil, key: key,
                    cells: cells, usage: nil))
            }
        }
        let snapshot = CoreLoadoutRows(usage: .ready, items: [], hooks: hooks, problems: [], events: events,
                                       roots: ["claude": "/Users/demo/.claude", "codex": "/Users/demo/.codex"], countsByScope: [:], rowFlags: flags)
        return LoadoutRows.build(snapshot, home: nil)
    }
}
