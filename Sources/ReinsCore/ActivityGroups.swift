import Foundation

/// A repeated failed command (or failing hook), grouped across sessions. Same fields as `Failure` in core/activity.mjs.
public struct ActivityFailure: Equatable, Sendable {
    public enum Kind: String, Sendable { case command, hook }

    public struct Hook: Equatable, Sendable {
        public var hash: String
        public var event: String
    }

    public var kind: Kind
    public var cli: ActivityCLI
    /// Command: sha of the normalized command. Hook: the inventory hash `sha(event|command)`.
    public var key: String
    /// The command, one form for every failure (a long one is cut at 120 characters).
    public var title: String
    public var count: Int
    public var exit: Int?
    public var reason: String
    public var projects: [String]
    public var sessions: Int
    public var first: String?
    public var last: String?
    /// The first passing run of the same command after the last failure. A timestamp only: it does not say the failure was fixed.
    public var laterPass: String?
    public var hook: Hook?
}

/// Edits of one file across sessions, with the shortest path suffix that tells it from the other files.
public struct ActivityFileRow: Equatable, Sendable {
    public var path: String
    public var label: String
    public var edits: Int
    public var sessions: Int
    public var last: String?
    public var clis: [ActivityCLI]
    public var projects: [String]
}

/// One folded log with the session name and project it belongs to.
struct ActivityLogEntry {
    var state: ActivityLogState
    var session: String
    var project: String?
}

/// Turns per-log states into the two cross-session lists of the Activity tab (core/activity-groups.mjs).
enum ActivityGroups {
    private static let titleMax = 120

    private static func iso(_ ms: Double) -> String? { ms.isFinite && ms > 0 ? ActivityText.isoString(ms) : nil }

    private static func title(_ cmd: String) -> String {
        cmd.utf16.count > titleMax ? ActivityText.prefix(cmd, titleMax - 1) + "…" : cmd
    }

    private struct Group {
        var kind: ActivityFailure.Kind
        var cli: ActivityCLI
        var key: String
        var title: String
        var hook: ActivityFailure.Hook?
        var count = 0
        var exit: Int?
        var reason = ""
        var projects = Set<String>()
        var sessions = Set<String>()
        var firstAt = Double.infinity
        var lastAt = 0.0
    }

    /// Failures group by CLI plus command (hooks by CLI plus hook hash).
    static func groupFailures(_ logs: [ActivityLogEntry], limit: Int) -> [ActivityFailure] {
        var order: [String] = []
        var groups: [String: Group] = [:]
        var seen = Set<String>()
        func add(_ cli: ActivityCLI, _ gkey: String, _ base: Group, id: String, at: Double, exit: Int?, reason: String, session: String, project: String?) {
            let dedupe = "\(cli.rawValue)|\(id)"
            if seen.contains(dedupe) { return } // forked or resumed logs repeat earlier events
            seen.insert(dedupe)
            var g: Group
            if let existing = groups[gkey] { g = existing } else { g = base; order.append(gkey) }
            g.count += 1
            g.sessions.insert(session)
            if let project { g.projects.insert(project) }
            g.firstAt = min(g.firstAt, at)
            if at >= g.lastAt { g.lastAt = at; g.exit = exit; g.reason = reason }
            groups[gkey] = g
        }
        for entry in logs {
            let st = entry.state
            for f in st.failures {
                let base = Group(kind: .command, cli: st.cli, key: f.key, title: title(f.cmd), hook: nil)
                add(st.cli, "\(st.cli.rawValue)|cmd|\(f.key)", base, id: f.id, at: f.at, exit: f.exit, reason: f.reason, session: entry.session, project: entry.project)
            }
            for h in st.hookFailures {
                let hash = ActivityFold.hookHash(event: h.event, command: h.command)
                let base = Group(kind: .hook, cli: st.cli, key: hash, title: title(h.command), hook: ActivityFailure.Hook(hash: hash, event: h.event))
                add(st.cli, "\(st.cli.rawValue)|hook|\(hash)", base, id: h.id, at: h.at, exit: h.exit, reason: h.reason, session: entry.session, project: entry.project)
            }
        }
        var passes: [String: [Double]] = [:]
        for entry in logs {
            for (key, list) in entry.state.passes {
                let k = "\(entry.state.cli.rawValue)|cmd|\(key)"
                if groups[k] != nil { passes[k, default: []].append(contentsOf: list) }
            }
        }
        let rows = order.compactMap { gkey -> ActivityFailure? in
            guard let g = groups[gkey] else { return nil }
            let later = (passes[gkey] ?? []).filter { $0 > g.lastAt }.min()
            return ActivityFailure(
                kind: g.kind, cli: g.cli, key: g.key, title: g.title, count: g.count, exit: g.exit, reason: g.reason,
                projects: ActivityText.sortedStrings(g.projects), sessions: g.sessions.count,
                first: iso(g.firstAt), last: iso(g.lastAt), laterPass: later.flatMap(iso), hook: g.hook
            )
        }
        // Newest first, then most repeated; ties keep the order the groups were first seen (a stable sort).
        let sorted = rows.enumerated().sorted { a, b in
            let la = a.element.last ?? "", lb = b.element.last ?? ""
            if la != lb { return la > lb }
            if a.element.count != b.element.count { return a.element.count > b.element.count }
            return a.offset < b.offset
        }.map(\.element)
        return Array(sorted.prefix(limit))
    }

    /// The shortest path suffix that no other path in the list shares. A path with no unique suffix keeps its whole text.
    static func shortestLabels(_ paths: [String]) -> [String] {
        let segments = paths.map { $0.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init) }
        var counts: [Int: [String: Int]] = [:]
        func suffix(_ parts: [String], _ k: Int) -> String { parts.suffix(k).joined(separator: "/") }
        func countsFor(_ k: Int) -> [String: Int] {
            if let cached = counts[k] { return cached }
            var m: [String: Int] = [:]
            for parts in segments where parts.count >= k { m[suffix(parts, k), default: 0] += 1 }
            counts[k] = m
            return m
        }
        return segments.enumerated().map { i, parts in
            if parts.isEmpty { return paths[i] }
            for k in 1...parts.count where countsFor(k)[suffix(parts, k)] == 1 { return suffix(parts, k) }
            return paths[i]
        }
    }

    private struct FileGroup {
        var path: String
        var edits = 0
        var sessions = Set<String>()
        var clis = Set<String>()
        var projects = Set<String>()
        var lastAt = 0.0
    }

    /// File history across logs; `label` is the shortest suffix that still tells two files apart.
    static func groupFiles(_ logs: [ActivityLogEntry], limit: Int) -> [ActivityFileRow] {
        var order: [String] = []
        var files: [String: FileGroup] = [:]
        var seen = Set<String>()
        for entry in logs {
            for e in ActivityFold.editsOf(entry.state) {
                if seen.contains(e.id) { continue }
                seen.insert(e.id)
                var f: FileGroup
                if let existing = files[e.path] { f = existing } else { f = FileGroup(path: e.path); order.append(e.path) }
                f.edits += 1
                f.sessions.insert(entry.session)
                f.clis.insert(entry.state.cli.rawValue)
                if let project = entry.project { f.projects.insert(project) }
                f.lastAt = max(f.lastAt, e.at)
                files[e.path] = f
            }
        }
        let ordered = order.compactMap { files[$0] }.enumerated().sorted { a, b in
            a.element.lastAt != b.element.lastAt ? a.element.lastAt > b.element.lastAt : a.offset < b.offset
        }.map(\.element)
        let rows = Array(ordered.prefix(limit))
        let labels = shortestLabels(rows.map(\.path))
        return rows.enumerated().map { i, f in
            ActivityFileRow(
                path: f.path, label: labels[i], edits: f.edits, sessions: f.sessions.count, last: iso(f.lastAt),
                clis: ActivityText.sortedStrings(f.clis).compactMap(ActivityCLI.init(rawValue:)), projects: ActivityText.sortedStrings(f.projects)
            )
        }
    }
}
