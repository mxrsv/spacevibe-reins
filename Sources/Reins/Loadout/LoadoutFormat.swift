import Foundation
import ReinsCore

/// A label above a row's name: text, tone and icon. Decided here so the row view only draws.
struct LoadoutTag: Equatable {
    var text: String
    var tone: TagTone = .neutral
    var icon: ReinsGlyph?
}

/// Wording and mapping of the Loadout screen. Pure.
enum LoadoutFormat {
    /// The engine says "Usage scan has not finished" for a pending cell while the scan runs. When the scan failed it will not
    /// finish, so the cell says that instead.
    static let scanPendingReason = "Usage scan has not finished"

    static func cellModel(_ state: UsageCellState, scanFailure: String?) -> UsageCellModel {
        switch state {
        case .counted(let runs, _, _): return .counted(runs: runs)
        case .pending(let reason):
            if let scanFailure, reason == scanPendingReason { return .pending(reason: "The usage scan failed: \(scanFailure)") }
            return .pending(reason: reason)
        case .unmeasurable(let reason): return .unmeasurable(reason: reason)
        case .missing: return .missing
        }
    }

    static func tags(_ row: LoadoutRow) -> [LoadoutTag] {
        var out: [LoadoutTag] = []
        if let plugin = row.plugin { out.append(LoadoutTag(text: "plugin: \(plugin)", icon: .lock)) }
        if row.flags.dead { out.append(LoadoutTag(text: "script not found", tone: .danger, icon: .scriptMissing)) }
        if row.errors > 0 { out.append(LoadoutTag(text: "\(row.errors) \(row.errors == 1 ? "error" : "errors")", tone: .warn)) }
        if let note = row.addedNote { out.append(LoadoutTag(text: note)) }
        return out
    }

    /// What the counts rest on. They come from every session log found, not a fixed window, so it says how many and since when.
    static func usageNote(result: UsageResult?, progress: UsageProgress?, failure: String?) -> String {
        if let result {
            let since = [result.windows.claude.oldest, result.windows.codex.oldest].compactMap { $0 }.min()
            let claude = result.sessions.claude.formatted(.number.locale(Locale(identifier: "en_US")))
            let codex = result.sessions.codex.formatted(.number.locale(Locale(identifier: "en_US")))
            return "Counted from \(claude) Claude Code and \(codex) Codex sessions" + (since.map { " since \($0)" } ?? "")
        }
        if failure != nil { return "Usage could not be counted" }
        if let progress, progress.total > 0 { return "Counting usage, \(progress.done) of \(progress.total) logs" }
        return "Counting usage"
    }

    static func removeLabel(row: LoadoutRow, member: LoadoutMember) -> String {
        let cli = member.cli.label
        if case .hook(let hook) = member { return "Removed \(hook.event) hook from \(cli)" }
        return "Removed \(row.kind.noun) \(row.name) from \(cli)"
    }

    static func addLabel(row: LoadoutRow, to cli: InventoryCLI) -> String {
        "Added \(row.kind.noun) \(row.name) to \(cli.label)"
    }

    static func removeAction(row: LoadoutRow, member: LoadoutMember) -> String {
        "Remove \(row.name) from \(member.cli.label)"
    }
}
