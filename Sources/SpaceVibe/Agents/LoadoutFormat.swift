import Foundation

/// Wording and mapping of the Loadout screen. Pure.
enum LoadoutFormat {
    /// The date of the oldest session log the scan read, over every CLI; nil when no log has a date.
    static func usageSince(_ result: CoreUsageResult?) -> String? {
        guard let result else { return nil }
        return result.windows.compactMap(\.oldest).min()
    }

    /// What the counts rest on. They come from every session log found, not a fixed window, so it says how many and since when.
    static func usageNote(result: CoreUsageResult?, progress: CoreUsageProgress?, failure: String?) -> String {
        if let result {
            let since = usageSince(result)
            let counts = result.sessions.map { "\($0.count.formatted(.number.locale(Locale(identifier: "en_US")))) \($0.cli.label)" }
            return "Counted from \(list(counts)) sessions" + (since.map { " since \($0)" } ?? "")
        }
        if failure != nil { return "Usage could not be counted" }
        if let progress, progress.total > 0 { return "Counting usage, \(progress.done) of \(progress.total) logs" }
        return "Counting usage"
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        return parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
    }

    static func removeLabel(row: LoadoutRow, member: LoadoutMember) -> String {
        let cli = member.cli.label
        if case .hook(let hook) = member { return "Removed \(hook.event) hook from \(cli)" }
        return "Removed \(row.kind.noun) \(row.name) from \(cli)"
    }

    static func addLabel(row: LoadoutRow, to cli: CLIID) -> String {
        "Added \(row.kind.noun) \(row.name) to \(cli.label)"
    }
}
