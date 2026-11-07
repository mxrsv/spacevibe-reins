import Foundation

/// Every sentence the Hooks tab shows (V5-R45, V5-R65, V5-R66), derived from the row and the one copy rule. Vocabulary follows
/// GLOSSARY.md: `Runs` count hooks only; a Codex hook's runs read `Unmeasurable`, never a number; a Claude Code hook with no
/// run reads `Never ran`.
enum HooksWording {
    // MARK: The warning slot

    /// What the warning slot holds, if anything: the danger triangle for a hook whose script is gone, the lock for a plugin's hook,
    /// the neutral clock for a hook whose runs nothing can count.
    struct Slot: Equatable {
        let mark: StateMark
        let sentence: String
        /// A hook that cannot run offers `Remove`, unless a plugin owns it.
        let offersRemove: Bool
    }

    static func slot(for row: LoadoutRow, home: String?) -> Slot? {
        if row.isDeadHook {
            let path = row.hookMembers.values.first(where: \.dead)?.paths.first
            let named = path.map { "Its script \(LoadoutRows.shorten($0, home: home)) is gone" } ?? "Its script is gone"
            return Slot(mark: StateMark(.danger, label: "Script is gone"), sentence: "\(named), so this hook can't run.",
                        offersRemove: row.plugin == nil)
        }
        if let plugin = row.plugin {
            return Slot(mark: StateMark(.lock, label: "Plugin-owned"), sentence: "Owned by the \(plugin) plugin. SpaceVibe can read it but not change it.",
                        offersRemove: false)
        }
        if row.isUnmeasurable {
            let codexOnly = row.presentCLIs == [.codex]
            return Slot(mark: StateMark(.clock, label: "Unmeasurable"),
                        sentence: codexOnly ? "Codex logs no hook runs, so SpaceVibe cannot count this hook's runs."
                            : "There is no log to count this hook's runs from.", offersRemove: false)
        }
        return nil
    }

    /// What VoiceOver reads for the row.
    static func spoken(_ row: LoadoutRow, home: String?) -> String {
        [row.hookTitle, row.hookEvent, row.hookMatcher.map { "matcher \($0)" }, slot(for: row, home: home)?.mark.label]
            .compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: The copy rule's sentences

    /// The reason in a few words, for a row of `Can't copy to Codex`.
    static func short(_ block: LoadoutRows.HookCopyBlock) -> String {
        switch block {
        case .notInstalled(let cli): "\(cli.label) is not installed"
        case .noEvent(_, let event): "No \(event) event"
        case .scriptGone: "Script is gone"
        case .plugin: "Owned by a plugin"
        case .notWritten(let cli): "SpaceVibe doesn't write \(cli.label) hooks"
        }
    }

    /// The reason as a sentence, for the detail, a toast and a row's spoken label.
    static func long(_ block: LoadoutRows.HookCopyBlock) -> String {
        switch block {
        case .notInstalled(let cli): "\(cli.label) is not installed on this Mac."
        case .noEvent(let cli, let event): "\(cli.label) has no \(event) event."
        case .scriptGone: "Its script is gone, so there is nothing to copy."
        case .plugin(let name): "It is owned by the \(name) plugin. SpaceVibe cannot change it."
        case .notWritten(let cli): "SpaceVibe does not write hooks into \(cli.label)."
        }
    }

    /// The order the reasons list in, in the card and in the `Why` popover.
    static func order(_ block: LoadoutRows.HookCopyBlock) -> Int {
        switch block {
        case .notInstalled: 0
        case .noEvent: 1
        case .scriptGone: 2
        case .plugin: 3
        case .notWritten: 4
        }
    }

    /// The `Why` popover: one paragraph per reason that some listed hook has. The Codex facts are the inventory's own lists and the
    /// core's own refusal; whether Codex would load a hook SpaceVibe wrote is not verified.
    static func why(_ entries: [HooksCantCopy.Entry]) -> [String] {
        var seen: Set<Int> = []
        var out: [String] = []
        for entry in entries where seen.insert(order(entry.block)).inserted {
            switch entry.block {
            case .noEvent:
                let events = Array(Set(entries.compactMap { entry -> String? in
                    if case .noEvent(_, let event) = entry.block { event } else { nil }
                })).sorted()
                out.append("Codex has no \(list(events)) \(events.count == 1 ? "event" : "events") in the list SpaceVibe reads (unverified), so a hook on \(events.count == 1 ? "it" : "them") has nothing to fire on.")
            case .scriptGone: out.append("A hook whose script is gone has nothing to copy.")
            case .plugin: out.append("A plugin's hook is read-only: SpaceVibe does not copy it.")
            case .notWritten: out.append("SpaceVibe does not write hooks into Codex. Codex runs a hook only after it is reviewed and trusted (Codex's hooks page), so a hook SpaceVibe wrote would not run until then.")
            case .notInstalled: out.append("Codex is not installed on this Mac.")
            }
        }
        return out
    }

    private static func list(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " or " + (items.last ?? "")
    }

    // MARK: The detail popover (V5-R57, V5-R66)

    /// "Event · matcher": the card rows' and the popover's sub line.
    static func eventLine(_ row: LoadoutRow) -> String {
        [row.hookEvent, row.hookMatcher].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// "In both CLIs" or "Claude Code only".
    static func presence(_ row: LoadoutRow) -> String {
        row.presentCLIs.count == 2 ? "In both CLIs" : "\(row.presentCLIs.first?.label ?? "No CLI") only"
    }

    static func runs(_ run: HookRun) -> String {
        switch run {
        case .ran(let count, _): "\(count) \(count == 1 ? "run" : "runs")"
        case .neverRan: "never ran"
        case .newlyAdded: "never ran yet, the settings file is new"
        case .unmeasurable: "runs Unmeasurable"
        case .loading: "counting runs"
        case .missing: ""
        }
    }

    /// One sentence per CLI: the handler kind, the matcher and the runs (or the reason it has none) where the hook is, and why not
    /// where it is not.
    static func lines(for row: LoadoutRow, context: HooksContext, home: String?) -> [String] {
        CoreCLI.allCases.compactMap { cli -> String? in
            guard context.detected.contains(cli) || row.members[cli] != nil else { return nil }
            if let hook = row.hookMembers[cli] {
                let matcher = hook.matcher.flatMap { $0.isEmpty ? nil : "matcher \($0)" } ?? "no matcher"
                if hook.dead {
                    let path = hook.paths.first.map { LoadoutRows.shorten($0, home: home) }
                    return "\(cli.label): command handler, \(matcher), script \(path ?? "") is gone."
                }
                return "\(cli.label): command handler, \(matcher), \(runs(row.hookRun(in: cli)))."
            }
            if let block = context.block(row, to: cli) { return "\(cli.label): not there. \(long(block))" }
            return "\(cli.label): not there. Press A to copy it."
        }
    }

    // MARK: Toasts (V5-R38)

    static func copyLabel(_ row: LoadoutRow, to cli: CoreCLI) -> String { "Copied \(row.hookTitle) to \(cli.label)" }

    /// A sentence only the success toast adds: a matcher names tools, and the two CLIs name their tools differently.
    static let matcherNote = "Tool names in a matcher can differ between the CLIs (unverified)."

    static func copyAllLabel(_ count: Int, to cli: CoreCLI) -> String { "Copied \(count) \(count == 1 ? "hook" : "hooks") to \(cli.label)" }

    /// `cli` nil: every copy.
    static func removeLabel(_ row: LoadoutRow, from cli: CoreCLI?) -> String {
        cli.map { "Removed the \($0.label) copy of \(row.hookTitle)" } ?? "Removed \(row.hookTitle)"
    }

    /// What a toast says when a request leaves nothing to write.
    static func nothingToChange(_ row: LoadoutRow, adding: Bool) -> String {
        if let plugin = row.plugin { return "\(row.hookTitle) is owned by the \(plugin) plugin. SpaceVibe cannot change it." }
        return adding ? "\(row.hookTitle) is already in every CLI that can take it." : "Nothing to remove here. Use Remove to delete the only copy."
    }

    /// The core's own line about hooks it does not list (a handler other than `command`), kept for the spine's footnote.
    static func isOtherTypesProblem(_ problem: String) -> Bool {
        problem.hasSuffix("of other types are not shown.") || problem.hasSuffix("of another type is not shown.")
    }
}
