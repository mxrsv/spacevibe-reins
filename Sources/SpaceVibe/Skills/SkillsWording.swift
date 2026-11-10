import Foundation

/// Every sentence the Skills tab shows about a skill, derived from the row's cells in one place (V5-R27, V5-R33, V5-R38,
/// V5-R45). Vocabulary follows GLOSSARY.md: skills have sessions, never runs; `Never ran`, `Unmeasurable`, no "dead", no
/// "pending". No time is invented: a skill's last session is a UTC day and its "added" fact is a file's modification time
/// (G7), so the notes say "in the last 24 hours" and never "2 hours ago".
enum SkillsWording {
    // MARK: The row's warning slot

    struct Warning: Equatable {
        enum Kind: Equatable { case neverRan, newlyAdded, unmeasurable }

        let kind: Kind
        /// The slot's accessible name and the popover's heading.
        let label: String
        let sentence: String
        /// A plugin's skill: the popover says it is read-only and offers no `Remove`.
        let plugin: String?
        /// Whether the popover offers `Remove`: not for a plugin's skill and not for one that cannot be counted.
        let offersRemove: Bool
    }

    static func warning(for row: LoadoutRow) -> Warning? {
        let usage = row.skillUsage
        // "Never ran in …" names the CLIs whose logs were counted, not every CLI that has the file.
        let clis = cliPhrase(usage.measured, either: true)
        switch usage.state {
        case .ran, .loading:
            return nil
        case .unmeasurable:
            return Warning(kind: .unmeasurable, label: "Unmeasurable", sentence: noLogsSentence(usage), plugin: row.plugin, offersRemove: false)
        case .neverRan:
            if let added = usage.added {
                return Warning(kind: .newlyAdded, label: "Never ran, newly added", sentence: "Never ran. \(addedPhrase(added)), so no session may have used it yet.",
                               plugin: row.plugin, offersRemove: row.plugin == nil)
            }
            return Warning(kind: .neverRan, label: "Never ran", sentence: "Never ran in \(clis). Nothing in the local logs shows a session.",
                           plugin: row.plugin, offersRemove: row.plugin == nil)
        }
    }

    static func addedPhrase(_ added: SkillCell.Added) -> String {
        switch added {
        case .lastDay: "Added in the last 24 hours"
        case .afterNewestLog: "Added after the newest log SpaceVibe counted"
        }
    }

    private static func noLogsSentence(_ usage: SkillUsage) -> String {
        let names = usage.withoutLogs.map(\.label)
        return "SpaceVibe found no \(names.isEmpty ? "logs" : names.joined(separator: " or ") + " logs"), so it cannot count sessions."
    }

    // MARK: The pane

    struct Verdict: Equatable {
        let status: SkillStatus
        let title: String
        let text: String
        let small: String?
    }

    /// The verdict panel; nil while the scan has not finished. `detected` are the CLIs on the machine, so "Codex does not have
    /// it" is not said of a CLI that is not installed. `since` is the date of the oldest log the scan read: Never ran says how far
    /// back it looked.
    static func verdict(for row: LoadoutRow, status: SkillStatus, detected: [CoreCLI], since: String? = nil) -> Verdict? {
        let usage = row.skillUsage
        let present = usage.present
        let ranIn = usage.ranIn
        let oneOnly = present.count == 1
        let lock = row.plugin.map { "Owned by the \($0) plugin, so SpaceVibe can read it but not change it." }
        let other = present.first.map(\.other)
        let missingElsewhere = oneOnly && other.map { detected.contains($0) } == true
        switch status {
        case .loading:
            return nil
        case .heavy:
            // Where the sessions happened, not where the file is: 142 in Claude Code and none in Codex is "all in Claude Code".
            // The count is the meter's: the sentence says where, not how many (V5-R60).
            let where_ = ranIn.count == 1 ? "only in \(ranIn[0].label)" : "in both CLIs"
            return Verdict(status: status, title: status.title, text: "Ran \(where_). One of the busiest skills you have.",
                           small: lock ?? (missingElsewhere ? "\(other?.label ?? "") does not have it yet." : idleNote(usage)))
        case .ran:
            if oneOnly {
                let text = "Used only in \(present[0].label)." + (missingElsewhere ? " \(other?.label ?? "") does not have it." : "")
                return Verdict(status: status, title: status.title, text: text,
                               small: lock ?? (missingElsewhere ? "Adding it gives \(other?.label ?? "") the same skill with a fresh count." : nil))
            }
            if ranIn.count == 1 {
                return Verdict(status: status, title: status.title, text: "Used only in \(ranIn[0].label).", small: lock ?? idleNote(usage))
            }
            return Verdict(status: status, title: status.title, text: "Used in both CLIs.", small: lock)
        case .neverRan:
            let measured = usage.measured
            let text: String
            let none = since.map { "No session in the local logs since \($0)" }
            if oneOnly {
                text = "Installed in \(present[0].label). " + (none.map { $0 + "." } ?? "Nothing in the local logs shows a session.")
            } else if measured.count == 2 {
                text = "Installed in both CLIs. " + (none.map { $0 + "." } ?? "Nothing in the local logs shows a session in either.")
            } else {
                let unlogged = usage.withoutLogs.map(\.label).joined(separator: " or ")
                let first = measured.first?.label ?? "either"
                text = "Installed in both CLIs. " + (none.map { "\($0) in \(first)" } ?? "Nothing in the local logs shows a session in \(first)")
                    + ", and SpaceVibe found no \(unlogged) logs."
            }
            let small = lock ?? (usage.added.map { "\(addedPhrase($0)), so it is not a candidate to remove yet." } ?? "A good candidate to remove.")
            return Verdict(status: status, title: status.title, text: text, small: small)
        case .unmeasurable:
            return Verdict(status: status, title: status.title, text: noLogsSentence(usage), small: "It shows a count once that CLI has logs.")
        }
    }

    /// A true quiet line about the CLI that has the skill but where no session used it, when another CLI's sessions did.
    private static func idleNote(_ usage: SkillUsage) -> String? {
        guard let idle = usage.present.first(where: { !usage.ranIn.contains($0) }) else { return nil }
        switch usage.cells[idle] {
        case .sessions: return "It has not run in \(idle.label)."
        case .added(let added):
            let when = added == .lastDay ? "in the last 24 hours" : "after the newest log SpaceVibe counted"
            return "It has not run in \(idle.label): that copy was added \(when)."
        case .noLogs: return "SpaceVibe found no \(idle.label) logs, so it cannot count sessions there."
        default: return nil
        }
    }

    static func sessions(_ count: Int) -> String { "\(count) \(count == 1 ? "session" : "sessions")" }

    /// "Claude Code", "Codex", "either CLI" or "both CLIs".
    private static func cliPhrase(_ clis: [CoreCLI], either: Bool) -> String {
        clis.count == 1 ? clis[0].label : (either ? "either CLI" : "both CLIs")
    }

    /// The meter of one CLI in "Sessions by CLI".
    static func meter(for row: LoadoutRow, cli: CoreCLI, maxSessions: Int, now: Date) -> SessionMeter {
        let name = cli.label
        let usage = row.skillUsage
        switch usage.cells[cli] ?? .missing {
        case .missing:
            let caption = row.plugin != nil ? "Plugin-owned skills stay in their CLI" : "\(name) does not have this skill."
            return SessionMeter(cli: cli, status: "Not in \(name)", figure: nil, share: nil, caption: caption, emphasis: nil)
        case .loading:
            return SessionMeter(cli: cli, status: nil, figure: nil, share: nil, caption: "Counting sessions", emphasis: nil)
        case .noLogs:
            return SessionMeter(cli: cli, status: nil, figure: nil, share: nil, caption: "No \(name) logs to count from", emphasis: nil)
        case .added(let added):
            return SessionMeter(cli: cli, status: nil, figure: 0, share: 0, caption: addedPhrase(added), emphasis: nil)
        case .sessions(let count, let last):
            let share = maxSessions > 0 ? Double(count) / Double(maxSessions) : 0
            let when = count == 0 ? "never" : last.map { SkillDays.phrase($0, now: now) }
            return SessionMeter(cli: cli, status: nil, figure: count, share: share, caption: "Last ran", emphasis: when ?? "unknown")
        }
    }

    // MARK: Toasts (V5-R38)

    static func addLabel(_ rows: [LoadoutRow], to cli: CoreCLI, skipped: Int) -> String {
        let what = rows.count == 1 ? rows[0].name : "\(rows.count) skills"
        return "Added \(what) to \(cli.label)" + skippedNote(skipped)
    }

    /// Skills added to different CLIs in one write ("a" on picks that each lack another CLI): no single CLI to name.
    static func addLabel(_ rows: [LoadoutRow], toEach skipped: Int, count: Int) -> String {
        "Added \(count == 1 ? rows[0].name : "\(count) skills") to the other CLI" + skippedNote(skipped)
    }

    static func removeLabel(_ rows: [LoadoutRow], from cli: CoreCLI?, skipped: Int) -> String {
        let what = rows.count == 1 ? rows[0].name : "\(rows.count) skills"
        return "Removed \(what)" + (cli.map { " from \($0.label)" } ?? "") + skippedNote(skipped)
    }

    private static func skippedNote(_ skipped: Int) -> String {
        skipped == 0 ? "" : " (\(skipped) left as they are)"
    }

    /// What VoiceOver reads after a bottom-bar logo's CLI name (V5-R43): "all selected skills are in Codex, press to remove them".
    static func bulkSpoken(_ rows: [LoadoutRow], cli: CoreCLI, isLit: Bool, mode: LogoToggleMode) -> String {
        let name = cli.label
        let skills = rows.count == 1 ? "the selected skill" : "all selected skills"
        switch mode {
        case .toggles: return isLit ? "\(skills) \(rows.count == 1 ? "is" : "are") in \(name), press to remove \(rows.count == 1 ? "it" : "them")"
            : "press to add \(skills.replacingOccurrences(of: "all selected", with: "the selected")) to \(name)"
        case .readOnly: return "read-only"
        case .onlyCopy: return "\(skills) \(rows.count == 1 ? "is" : "are") in \(name), the only copy; use Remove to delete"
        }
    }

    /// What a toast says when a request leaves nothing to write: a plugin's or a project's skill, an only copy.
    static func nothingToChange(_ rows: [LoadoutRow], adding: Bool) -> String {
        if rows.contains(where: { $0.plugin != nil }) { return "Plugin-owned skills cannot be changed here." }
        if rows.contains(where: { $0.project != nil }) { return "Project skills cannot be changed here." }
        return adding ? "Nothing to add: the skill is already there." : "Nothing to remove here. Use Remove to delete a skill that is only in one CLI."
    }
}
