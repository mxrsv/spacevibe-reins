import Foundation

/// Every sentence the Subagents tab shows about a subagent (V5-R45, V5-R63, V5-R64), derived from the row's cells. A subagent's
/// usage cells read as a skill's, so the warning and verdict wording is `SkillsWording`'s (generic: no sentence of it names a
/// skill). Vocabulary follows GLOSSARY.md: sessions, never runs; no model, tools or "can run Bash" (G1), and no time of day
/// (the "added" fact is a file's modification time, G7).
enum SubagentsWording {
    // MARK: The row

    /// The text before the logos: "142 sessions", "never ran" (also a file too new to have run, S3), "unmeasurable",
    /// "counting" while the scan runs.
    static func sessionsText(_ row: LoadoutRow) -> String {
        let usage = row.skillUsage
        switch usage.state {
        case .ran: return SkillsWording.sessions(usage.sessions ?? 0)
        case .neverRan: return "never ran"
        case .unmeasurable: return "unmeasurable"
        case .loading: return "counting"
        }
    }

    /// What the warning slot holds, if anything: the lock for a plugin's subagent (the usage fact joins its sentence), the triangle
    /// for one that never ran, the neutral clock for a new or unmeasurable one.
    struct Slot: Equatable {
        let mark: StateMark
        let sentence: String?
        let plugin: String?
        let offersRemove: Bool
    }

    static func slot(for row: LoadoutRow) -> Slot? {
        let usage = SkillsWording.warning(for: row)
        if let plugin = row.plugin {
            return Slot(mark: StateMark(.lock, label: "Plugin-owned"), sentence: usage?.sentence, plugin: plugin, offersRemove: false)
        }
        guard let usage else { return nil }
        return Slot(mark: StateMark(usage.kind == .neverRan ? .warn : .clock, label: usage.label), sentence: usage.sentence, plugin: nil,
                    offersRemove: usage.offersRemove)
    }

    /// What VoiceOver reads for the row.
    static func spoken(_ row: LoadoutRow) -> String {
        [row.name, sessionsText(row), slot(for: row)?.mark.label].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: The Answer

    static func verdict(for row: LoadoutRow, detected: [CoreCLI], since: String? = nil) -> SubagentsAnswer.Verdict {
        let said = SkillsWording.verdict(for: row, status: .neverRan, detected: detected, since: since)
        return SubagentsAnswer.Verdict(key: row.key, name: row.name, text: said?.text ?? "Nothing in the local logs shows a session.",
                                       small: said?.small, offersRemove: row.plugin == nil)
    }

    // MARK: The detail popover (V5-R57)

    /// "In both CLIs" or "Claude Code only".
    static func presence(_ row: LoadoutRow) -> String {
        row.presentCLIs.count == 2 ? "In both CLIs" : "\(row.presentCLIs.first?.label ?? "No CLI") only"
    }

    /// One sentence per CLI that has the subagent: its sessions and the day of the last one. The inventory carries no model or
    /// tools (G1), so the popover says nothing about them.
    static func lines(for row: LoadoutRow, now: Date) -> [String] {
        row.presentCLIs.map { cli in
            let name = cli.label
            switch row.skillUsage.cells[cli] ?? .missing {
            case .sessions(let count, let last):
                guard count > 0 else { return "\(name): never ran." }
                return "\(name): \(SkillsWording.sessions(count))" + (last.map { ", last session \(SkillDays.phrase($0, now: now))" } ?? "") + "."
            case .added(let added): return "\(name): never ran. \(SkillsWording.addedPhrase(added))."
            case .noLogs: return "\(name): no logs to count sessions from."
            case .loading: return "\(name): counting sessions."
            case .missing: return "\(name): not installed."
            }
        }
    }

    /// What the detail popover shows for a row: `lines`, then, when `Add to <CLI>` is offered, what that copy carries (G10), so the
    /// sentence is read before the click.
    static func detailLines(for row: LoadoutRow, adding target: CoreCLI?, now: Date) -> [String] {
        lines(for: row, now: now) + (target.map { [copyNote(to: $0)] } ?? [])
    }

    /// The sentences under the `In one CLI only` list: one per CLI a row there would be added to, in list order.
    static func addableNotes(_ addable: SubagentsAddable) -> [String] {
        var targets: [CoreCLI] = []
        for entry in addable.entries where !targets.contains(entry.target) { targets.append(entry.target) }
        return targets.map { copyNote(to: $0) }
    }

    // MARK: Toasts (V5-R38)

    /// What a copy into `cli` carries, said before `Add to <CLI>` (G10, owner call C3): name, description and instructions. For
    /// Claude Code it adds what follows from the missing `tools` line (see `addNote`).
    static func copyNote(to cli: CoreCLI) -> String {
        let base = "A copy added to \(cli.label) carries its name, description and instructions, not its model or tools"
        return cli == .claude ? base + ", so it can use every tool." : base + "."
    }

    static func addLabel(_ row: LoadoutRow, to cli: CoreCLI) -> String { "Added \(row.name) to \(cli.label)" }

    /// What the copy really writes (G10): the file's name, description and instructions. Nothing of its model or tools. A Claude
    /// Code subagent with no `tools` line "inherits every tool available to subagents" (Claude Code's subagent docs), so the toast
    /// says that of a copy made into Claude Code. Codex's reading of a file with no model is not verified, so it is not said.
    static func addNote(to cli: CoreCLI) -> String {
        cli == .claude ? "Its model and tools are not copied, so it can use every tool." : "Its model and tools are not copied."
    }

    /// `cli` nil: every copy.
    static func removeLabel(_ row: LoadoutRow, from cli: CoreCLI?) -> String {
        cli.map { "Removed the \($0.label) copy of \(row.name)" } ?? "Removed \(row.name)"
    }

    /// What a toast says when a request leaves nothing to write.
    static func nothingToChange(_ row: LoadoutRow, adding: Bool) -> String {
        if let plugin = row.plugin { return "\(row.name) is owned by the \(plugin) plugin. SpaceVibe cannot change it." }
        if row.project != nil { return "\(row.name) belongs to a project. SpaceVibe cannot change it." }
        return adding ? "\(row.name) is already in every CLI that can take it." : "Nothing to remove here. Use Remove to delete the only copy."
    }
}
