import Foundation
import ReinsCore

/// What the lanes and the badge show, derived from one report. Pure: the screen only lays these out.
enum ActivityRows {
    static let failurePage = 8
    static let filePage = 25
    /// A failure group counts toward the sidebar badge when its last failure is this recent.
    static let recentFailureMs = 24 * 60 * 60 * 1000.0

    /// An ended process is not "running"; the engine keeps it listed for a few minutes only so it does not vanish unexplained.
    static func sessions(_ report: ActivityReport, cli: InventoryCLI) -> [ActivitySession] {
        report.sessions.filter { $0.cli == cli && $0.state != .ended }
    }

    static func failures(_ report: ActivityReport, cli: InventoryCLI) -> [ActivityFailure] {
        report.failures.filter { $0.cli == cli }
    }

    static func limits(_ report: ActivityReport, cli: InventoryCLI) -> [ActivityLimit] {
        report.unmeasurable.filter { $0.cli == cli }
    }

    static func recentFailureCount(_ report: ActivityReport?, now: Date) -> Int {
        guard let report else { return 0 }
        return report.failures.filter { f in
            guard let last = ActivityFormat.date(f.last) else { return false }
            return now.timeIntervalSince(last) * 1000 < recentFailureMs
        }.count
    }

    /// How many more rows a "Show more" row reveals, and how many stay hidden after that.
    static func nextPage(shown: Int, total: Int, page: Int) -> (reveal: Int, hiddenAfter: Int)? {
        guard total > shown else { return nil }
        let reveal = min(page, total - shown)
        return (reveal, total - shown - reveal)
    }
}

/// How a live session reads in its row: the tag, the muted second line, the help text.
struct SessionWording {
    let tagText: String
    let tagTone: TagTone
    let tagIcon: String?
    /// The engine's reason, shown as help for every state so "why" is always one hover away.
    let help: String
    let subtitle: String

    init(_ session: ActivitySession, elapsedMs: Double) {
        switch session.state {
        case .running: (tagText, tagTone, tagIcon) = ("running", session.cli.tagTone, nil)
        case .waiting: (tagText, tagTone, tagIcon) = ("waiting for you", .warn, nil)
        case .unmeasurable: (tagText, tagTone, tagIcon) = ("not measurable", .neutral, "exclamationmark.triangle")
        case .idle, .ended: (tagText, tagTone, tagIcon) = ("idle", .neutral, nil)
        }
        help = session.stateReason
        var parts: [String] = []
        if let project = session.project { parts.append(project) }
        if session.state == .waiting {
            parts.append("needs your answer")
        } else if let tool = session.currentTool {
            parts.append(tool.target.isEmpty ? tool.name : "\(tool.name) · \(tool.target)")
        } else if session.state == .unmeasurable {
            parts.append("state not measurable")
        }
        if let ago = session.lastWriteAgoMs {
            let ms = ago + elapsedMs
            parts.append(ms < 60_000 ? "just now" : "\(ActivityFormat.span(ms)) ago")
        } else if let age = session.ageMs {
            parts.append("started \(ActivityFormat.span(age + elapsedMs)) ago")
        }
        subtitle = parts.joined(separator: " · ")
    }
}

/// The second, third and fourth lines of a failure row. One title form (the command) sits above them.
struct FailureWording {
    let how: String
    let reason: String?
    let laterPass: String?

    init(_ failure: ActivityFailure, now: Date) {
        var head: [String] = []
        if failure.kind == .hook, let hook = failure.hook { head.append("\(hook.event) hook") }
        if let exit = failure.exit { head.append("exit \(exit)") }
        if let projects = ActivityFormat.projects(failure.projects) { head.append(projects) }
        head.append("last \(ActivityFormat.ago(failure.last, now: now))")
        how = head.joined(separator: " · ")
        // "Exit 2" alone repeats the exit code, so the reason shows only when it says more.
        let plain = failure.reason.range(of: #"^Exit \d+$"#, options: .regularExpression) != nil
        reason = failure.reason.isEmpty || plain || failure.reason == "Hook failed" ? nil : failure.reason
        laterPass = ActivityFormat.laterPass(failure, now: now)
    }
}
