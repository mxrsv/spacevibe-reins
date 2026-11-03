import Foundation

/// Codex writes its rate limits into every `token_count` event of a rollout (spec, Limits). The newest such event in the
/// most recently written logs is the reading; its `primary` and `secondary` objects are the windows.
enum LimitsCodexLogs {
    /// Only the end of a log is read: the event repeats after every turn.
    static let tailBytes = 4 << 20
    /// Logs tried, newest first, before giving up. A brand-new session may not have logged a turn yet.
    static let filesTried = 3

    static func read(_ roots: Roots) -> CLILimits {
        guard Limits.isDirectory(roots.codex.root) else { return CLILimits(cli: .codex, state: .notInstalled) }
        var failed = false
        for url in newestLogs(roots.codex.logs) {
            switch lastEvent(in: url) {
            case .none: continue
            case .failed: failed = true
            case .line(let line): return reading(line)
            }
        }
        return CLILimits(cli: .codex, state: failed ? .unreadable : .notRecorded)
    }

    /// Logs by modification time, newest first: a resumed session appends to its old file in an older date folder.
    static func newestLogs(_ folder: URL) -> [URL] {
        let stamped: [(URL, Double)] = LogFiles.walk(folder).compactMap { url in
            var info = stat()
            guard stat(url.path, &info) == 0 else { return nil }
            let t = modificationTime(info)
            return (url, Double(t.tv_sec) + Double(t.tv_nsec) / 1e9)
        }
        return stamped.sorted { $0.1 > $1.1 }.prefix(filesTried).map(\.0)
    }

    enum TailEvent { case none, failed, line(Data) }

    /// The last `token_count` line whose `rate_limits` is an object (a null one is skipped) in the tail of the log.
    static func lastEvent(in url: URL) -> TailEvent {
        var last: Data?
        do {
            try LogFiles.reader(for: url, maxBytes: tailBytes).read { line in
                if ActivityText.contains(line, "\"type\":\"token_count\""), ActivityText.contains(line, "\"rate_limits\":{") {
                    last = line
                }
            }
        } catch {
            return .failed
        }
        return last.map(TailEvent.line) ?? .none
    }

    /// `{ timestamp, payload: { rate_limits: { primary, secondary, plan_type } } }`. A window in a shape this code does not
    /// know makes the reading unreadable rather than showing the other window alone.
    static func reading(_ line: Data) -> CLILimits {
        guard let document = try? OrderedJSON(data: line),
              let at = document.root.limitsMember("timestamp")?.stringValue.flatMap(ActivityText.parseTimestamp),
              let limits = document.root.limitsMember("payload")?.limitsMember("rate_limits") else {
            return CLILimits(cli: .codex, state: .unreadable)
        }
        let observed = Date(timeIntervalSince1970: at / 1000)
        var windows: [LimitWindow] = []
        for id in ["primary", "secondary"] {
            guard let raw = limits.limitsMember(id) else { continue }
            guard let window = window(id: id, raw, observed: observed) else { return CLILimits(cli: .codex, state: .unreadable) }
            windows.append(window)
        }
        let plan = limits.limitsMember("plan_type")?.stringValue
        if windows.isEmpty { return CLILimits(cli: .codex, state: .notRecorded, plan: plan) }
        return CLILimits(cli: .codex, state: .measured(at: observed, windows: windows), plan: plan)
    }

    /// `{ used_percent, window_minutes, resets_at }`, or the older `resets_in_seconds` counted from the event time.
    static func window(id: String, _ raw: JSONValue, observed: Date) -> LimitWindow? {
        guard let used = raw.limitsMember("used_percent")?.limitsNumber, used >= 0 else { return nil }
        let resetsAt: Date
        if let seconds = raw.limitsMember("resets_at")?.limitsNumber {
            resetsAt = Date(timeIntervalSince1970: seconds)
        } else if let relative = raw.limitsMember("resets_in_seconds")?.limitsNumber {
            resetsAt = observed.addingTimeInterval(relative)
        } else {
            return nil
        }
        let minutes = raw.limitsMember("window_minutes")?.limitsNumber.flatMap { $0 > 0 && $0 == $0.rounded() ? Int($0) : nil }
        return LimitWindow(id: id, minutes: minutes, scope: nil, usedPercent: used, resetsAt: resetsAt, active: true)
    }
}
