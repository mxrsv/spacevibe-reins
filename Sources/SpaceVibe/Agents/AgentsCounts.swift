import Foundation

/// The counts the Agents page shows: one per tab and the total the sidebar's Agents item carries. A count is nil until the
/// read it comes from has landed, and stays nil when that read failed, so the UI never shows a 0 it does not know (V5-R75).
///
/// Skills, subagents and hooks are the rows of the global scope that `loadout.rows` returns (a skill present in both CLIs is
/// one row), the same rows the old Loadout's badge counted; Rules is the number of rules in the global settings file.
struct AgentsCounts: Equatable {
    var skills: Int?
    var subagents: Int?
    var hooks: Int?
    var rules: Int?
    /// Skills, subagents and hooks together: the sidebar's Agents count.
    var total: Int?

    init(loadout: LoadoutData?, rules: Int?) {
        self.rules = rules
        guard let loadout else { return }
        let global = LoadoutRows.inScope(loadout.rows, scope: LoadoutRows.globalScope)
        func count(_ kind: LoadoutKind) -> Int { global.filter { $0.kind == kind }.count }
        skills = count(.skill)
        subagents = count(.agent)
        hooks = count(.hook)
        total = loadout.globalCount
    }

    func count(for category: AgentsCategory) -> Int? {
        switch category {
        case .skills: skills
        case .subagents: subagents
        case .hooks: hooks
        case .rules: rules
        }
    }
}
