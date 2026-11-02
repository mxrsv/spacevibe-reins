import Foundation

/// Writing a grid cell: replace the cell's rules in ONE settings file with canonical ones.
///
///     Read -> `Read`    Edit -> `Edit`    Run -> `Bash`    Network -> `WebFetch` + `WebSearch`
///     Push and deploy -> `Bash(git push *)` + `Bash(vercel *)`    Secrets -> `Read(./.env)` + `Read(./.env.*)`
///
/// Which rules a write replaces: the cell's wide rules (Read, Edit, Run, Network) or its own rules (Push and deploy,
/// Secrets). Narrow rules are never touched. A `mixed` cell is refused.
extension Rules {
    public static let pushRules = ["Bash(git push *)", "Bash(vercel *)"]
    public static let secretRules = ["Read(./.env)", "Read(./.env.*)"]

    static func replacedRole(_ capability: Capability) -> Role {
        switch capability {
        case .read, .edit, .run, .network: return .wide
        case .push, .secrets: return .own
        }
    }

    static func canonicalRules(_ capability: Capability) -> [String] {
        switch capability {
        case .read: return ["Read"]
        case .edit: return ["Edit"]
        case .run: return ["Bash"]
        case .network: return ["WebFetch", "WebSearch"]
        case .push: return pushRules
        case .secrets: return secretRules
        }
    }
}

extension RulesStore {
    struct CapabilityPlan {
        let capability: Capability
        let verdict: RuleVerdict
        let scope: RuleScope
        let current: CapabilityState
        let resulting: CapabilityState
        let replaces: [VerdictRule]
        let writes: [VerdictRule]
    }

    func plan(scope: RuleScope, capability: Capability, verdict: RuleVerdict) throws -> CapabilityPlan {
        let listing = try listRules([scope])
        if let problem = listing.problems.first {
            // The problem ends with a period already; keep one.
            throw ReinsError("\(problem.hasSuffix(".") ? problem : problem + ".") Nothing was changed.", status: 409)
        }
        let cell = Rules.capabilityGrid(listing.rules).first { $0.capability == capability }!
        guard cell.state != .mixed else {
            throw ReinsError("\(capability.label) has rules for specific paths or commands here, so it has no single value. Edit the individual rules instead.", status: 409)
        }
        let role = Rules.replacedRole(capability)
        let replaces = listing.rules.filter { item in
            guard let parsed = Rules.parseRule(item.rule) else { return false }
            return Rules.placements(parsed).contains { $0.0 == capability && $0.1 == role }
        }
        let writes = Rules.canonicalRules(capability).map { VerdictRule(verdict: verdict, rule: $0) }
        let kept = listing.rules.filter { item in !replaces.contains(item) }
        let resulting = Rules.capabilityGrid(kept + writes.map { RuleItem(verdict: $0.verdict, rule: $0.rule) }).first { $0.capability == capability }!.state
        return CapabilityPlan(
            capability: capability, verdict: verdict, scope: scope, current: cell.state, resulting: resulting,
            replaces: replaces.map(\.entry), writes: writes
        )
    }

    /// What a cell write would remove and write. Writes nothing. `resulting` differs from `verdict` when a rule that is
    /// kept (for example a bare `Bash` deny for Push and deploy) still wins.
    public func previewSetCapability(scope: RuleScope, capability: Capability, verdict: RuleVerdict) throws -> CapabilityPreview {
        let plan = try plan(scope: scope, capability: capability, verdict: verdict)
        return CapabilityPreview(
            capability: capability, verdict: verdict, scopeLabel: scope.fileLabel, current: plan.current, resulting: plan.resulting,
            replaces: plan.replaces, writes: plan.writes
        )
    }

    /// Replaces the cell's rules and records a journal entry. Nil when the file already holds exactly that.
    @discardableResult
    public func setCapability(scope: RuleScope, capability: Capability, verdict: RuleVerdict) throws -> JournalEntry? {
        let plan = try plan(scope: scope, capability: capability, verdict: verdict)
        return try edit(scope, label: "Set \(capability.label) to \(verdict.title) (\(scope.journalLabel))") { file, document in
            try RulesSettingsFile.edit(document, file: file, remove: plan.replaces, add: plan.writes)
        }
    }
}
