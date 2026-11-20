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
            // A hook only one CLI has, and that CLI logs no hook runs: say which.
            let silent = row.presentCLIs.count == 1 ? row.presentCLIs.first.flatMap { $0.identity.logsHookRuns ? nil : $0 } : nil
            return Slot(mark: StateMark(.clock, label: "Unmeasurable"),
                        sentence: silent.map { "\($0.label) logs no hook runs, so SpaceVibe cannot count this hook's runs." }
                            ?? "There is no log to count this hook's runs from.", offersRemove: false)
        }
        return nil
    }

    /// What VoiceOver reads for the row.
    static func spoken(_ row: LoadoutRow, home: String?) -> String {
        [row.hookTitle, row.hookEvent, row.hookMatcher.map { "matcher \($0)" }, slot(for: row, home: home)?.mark.label]
            .compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: The copy rule's sentences

    /// The reason in a few words.
    static func short(_ block: LoadoutRows.HookCopyBlock) -> String {
        switch block {
        case .notInstalled(let cli): "\(cli.label) is not installed"
        case .absent(let cli): "\(cli.label) has no hooks"
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
        case .absent(let cli): "\(cli.label) has no hooks, so there is nowhere to copy it."
        case .noEvent(let cli, let event): "\(cli.label) has no \(event) event."
        case .scriptGone: "Its script is gone, so there is nothing to copy."
        case .plugin(let name): "It is owned by the \(name) plugin. SpaceVibe cannot change it."
        case .notWritten(let cli): "SpaceVibe does not write hooks into \(cli.label)."
        }
    }

    /// The order `HooksCantCopy` lists the reasons in.
    static func order(_ block: LoadoutRows.HookCopyBlock) -> Int {
        switch block {
        case .notInstalled, .absent: 0
        case .noEvent: 1
        case .scriptGone: 2
        case .plugin: 3
        case .notWritten: 4
        }
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

    /// `scanFailed`: the usage scan failed, so a hook without a count is not being counted any more.
    static func runs(_ run: HookRun, scanFailed: Bool = false) -> String {
        switch run {
        case .ran(let count, _): "\(count) \(count == 1 ? "run" : "runs")"
        case .neverRan: "never ran"
        case .newlyAdded: "never ran yet, the settings file is new"
        case .unmeasurable: "runs Unmeasurable"
        case .loading: scanFailed ? "runs not counted" : "counting runs"
        case .missing, .absent: ""
        }
    }

    /// One sentence per CLI: the handler kind, the matcher and the runs (or the reason it has none) where the hook is, and why not
    /// where it is not.
    static func lines(for row: LoadoutRow, context: HooksContext, home: String?, scanFailed: Bool = false) -> [String] {
        CLICatalog.current.inventoryCLIs.compactMap { cli -> String? in
            guard context.detected.contains(cli) || row.members[cli] != nil else { return nil }
            if let hook = row.hookMembers[cli] {
                let matcher = hook.matcher.flatMap { $0.isEmpty ? nil : "matcher \($0)" } ?? "no matcher"
                if hook.dead {
                    let path = hook.paths.first.map { LoadoutRows.shorten($0, home: home) }
                    return "\(cli.label): command handler, \(matcher), script \(path ?? "") is gone."
                }
                return "\(cli.label): command handler, \(matcher), \(runs(row.hookRun(in: cli), scanFailed: scanFailed))."
            }
            if case .absent = context.block(row, to: cli) { return "\(cli.label) has no hooks." }
            if let block = context.block(row, to: cli) { return "\(cli.label): not there. \(long(block))" }
            return "\(cli.label): not there. Press A to copy it."
        }
    }

    // MARK: Toasts (V5-R38)

    static func copyLabel(_ row: LoadoutRow, to cli: CLIID) -> String { "Copied \(row.hookTitle) to \(cli.label)" }

    /// A sentence only the success toast adds: a matcher names tools, and the two CLIs name their tools differently.
    static let matcherNote = "Tool names in a matcher can differ between the CLIs (unverified)."

    static func copyAllLabel(_ count: Int, to cli: CLIID) -> String { "Copied \(count) \(count == 1 ? "hook" : "hooks") to \(cli.label)" }

    /// `cli` nil: every copy.
    static func removeLabel(_ row: LoadoutRow, from cli: CLIID?) -> String {
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
