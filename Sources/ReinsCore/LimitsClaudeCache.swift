import Foundation

/// Claude Code's own usage cache, `cachedUsageUtilization` in its global state file (spec, Limits). The format is
/// undocumented and Claude Code refreshes it only when it fetches usage itself, so the reading carries its fetch time.
/// Only `fetchedAtMs` and `utilization.limits[]` are read; the file also holds account data, which is never kept.
/// One entry in a shape this code does not know makes the whole reading unreadable: a partial list could hide the
/// window that is nearly used up.
enum LimitsClaudeCache {
    /// A state file past this is not parsed. The owner's is about 0.4 MB.
    static let maxBytes = 64 << 20
    static let weekMinutes = 7 * 24 * 60
    static let sessionMinutes = 5 * 60

    static func read(_ roots: Roots) -> CLILimits {
        let file = roots.claudeState
        guard FileManager.default.fileExists(atPath: file.path) else {
            return CLILimits(cli: .claude, state: Limits.isDirectory(roots.claude.root) ? .notRecorded : .notInstalled)
        }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue,
              size <= maxBytes,
              let data = try? Data(contentsOf: file),
              let document = try? OrderedJSON(data: data) else {
            return CLILimits(cli: .claude, state: .unreadable)
        }
        guard let cache = document.root.limitsMember("cachedUsageUtilization") else {
            return CLILimits(cli: .claude, state: .notRecorded)
        }
        return CLILimits(cli: .claude, state: state(of: cache))
    }

    static func state(of cache: JSONValue) -> CLILimits.State {
        guard let fetchedMs = cache.limitsMember("fetchedAtMs")?.limitsNumber,
              let entries = cache.limitsMember("utilization")?.limitsMember("limits")?.arrayValue else { return .unreadable }
        var windows: [LimitWindow] = []
        for entry in entries {
            guard let window = window(entry) else { return .unreadable }
            windows.append(window)
        }
        if windows.isEmpty { return .notRecorded }
        return .measured(at: Date(timeIntervalSince1970: fetchedMs / 1000), windows: windows)
    }

    /// `{ kind, group, percent, resets_at, scope: { model: { display_name } }, is_active }`.
    static func window(_ entry: JSONValue) -> LimitWindow? {
        guard let kind = entry.limitsMember("kind")?.stringValue,
              let percent = entry.limitsMember("percent")?.limitsNumber, percent >= 0,
              let resetText = entry.limitsMember("resets_at")?.stringValue,
              let resetMs = ActivityText.parseTimestamp(resetText) else { return nil }
        let group = entry.limitsMember("group")?.stringValue
        let scope = entry.limitsMember("scope")?.limitsMember("model")?.limitsMember("display_name")?.stringValue
        return LimitWindow(
            id: scope.map { "\(kind):\($0)" } ?? kind,
            minutes: minutes(kind: kind, group: group),
            scope: scope,
            usedPercent: percent,
            resetsAt: Date(timeIntervalSince1970: resetMs / 1000),
            active: entry.limitsMember("is_active")?.boolValue ?? true
        )
    }

    /// Seen on the owner's Mac: `weekly_all` and `weekly_scoped` in group `weekly`. The five-hour names are the ones the
    /// cache's own top-level keys use; any other name leaves the length unknown rather than guessed.
    static func minutes(kind: String, group: String?) -> Int? {
        if group == "weekly" || kind.hasPrefix("weekly") || kind.hasPrefix("seven_day") { return weekMinutes }
        if group == "session" || kind.hasPrefix("session") || kind.hasPrefix("five_hour") { return sessionMinutes }
        return nil
    }
}
