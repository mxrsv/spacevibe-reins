import Foundation

/// The capability grid: one state per capability, derived from concrete rules. Pure; no file is read.
///
///     Rule shape                                         Capability   Role in the cell
///     Read (bare, Read(), Read(*))                       Read files   wide        (also Secrets, wide)
///     Read(<path>)                                       Read files   narrow
///     Read(<path>) naming .env (Read(./.env*))           Secrets      own
///     Edit | Write | MultiEdit (bare or *)               Edit files   wide
///     Edit | Write | MultiEdit (<path>)                  Edit files   narrow
///     Bash (bare, Bash(*))                               Run commands wide        (also Push and deploy, wide)
///     Bash(<command>) except push and deploy prefixes    Run commands narrow
///     Bash(git push ..) Bash(vercel ..) and the other    Push+deploy  own
///       deploy-like prefixes
///     WebFetch | WebSearch (bare or *)                   Network      wide
///     WebFetch(..) | WebSearch(..)                       Network      narrow
///     anything else (mcp__*, Skill, Task, ...)           no cell
///
/// State of a cell (deny beats ask beats allow, as in Claude Code):
///     no rule at all                                     none
///     a wide deny                                        deny
///     wide ask   + narrow deny                           mixed;  wide ask   otherwise: ask
///     wide allow + narrow deny or ask                    mixed;  wide allow otherwise: allow
///     narrow rules only                                  mixed   (a scoped rule is not a cell value)
///     own rules only (Push and deploy, Secrets)          their verdict when all agree, else mixed
///     wide + own rules                                   strongest verdict among all of them
extension Rules {
    enum Role { case wide, own, narrow }

    static func placements(_ rule: ParsedRule) -> [(Capability, Role)] {
        let wide = isWide(rule)
        switch rule.tool {
        case "Read":
            if wide { return [(.read, .wide), (.secrets, .wide)] }
            return namesEnvFile(rule.specifier ?? "") ? [(.secrets, .own)] : [(.read, .narrow)]
        case "Edit", "Write", "MultiEdit":
            return [(.edit, wide ? .wide : .narrow)]
        case "Bash":
            if wide { return [(.run, .wide), (.push, .wide)] }
            return looksLikePushOrDeploy(rule.specifier ?? "") ? [(.push, .own)] : [(.run, .narrow)]
        case "WebFetch", "WebSearch":
            return [(.network, wide ? .wide : .narrow)]
        default:
            return []
        }
    }

    private static func strongest(_ verdicts: Set<RuleVerdict>) -> CapabilityState? {
        if verdicts.contains(.deny) { return .deny }
        if verdicts.contains(.ask) { return .ask }
        if verdicts.contains(.allow) { return .allow }
        return nil
    }

    private static func cellState(wide: [RuleItem], own: [RuleItem], narrow: [RuleItem]) -> CapabilityState {
        if wide.isEmpty, own.isEmpty, narrow.isEmpty { return .none }
        let w = Set(wide.map(\.verdict))
        if w.contains(.deny) { return .deny }
        let o = Set(own.map(\.verdict))
        if narrow.isEmpty {
            if own.isEmpty { return strongest(w) ?? .none }
            if !wide.isEmpty { return strongest(w.union(o)) ?? .none }
            return o.count == 1 ? CapabilityState(rawValue: o.first!.rawValue)! : .mixed
        }
        let n = Set(narrow.map(\.verdict))
        if w.contains(.ask) { return n.contains(.deny) ? .mixed : .ask }
        if w.contains(.allow) { return n.contains(.deny) || n.contains(.ask) ? .mixed : .allow }
        return .mixed
    }

    /// Rules from one scope or several: the same function sees one flat list.
    public static func capabilityGrid(_ rules: [RuleItem]) -> [CapabilityCell] {
        var cells: [Capability: (wide: [RuleItem], own: [RuleItem], narrow: [RuleItem])] = [:]
        for item in rules {
            guard let parsed = parseRule(item.rule) else { continue }
            for (capability, role) in placements(parsed) {
                var cell = cells[capability] ?? ([], [], [])
                switch role {
                case .wide: cell.wide.append(item)
                case .own: cell.own.append(item)
                case .narrow: cell.narrow.append(item)
                }
                cells[capability] = cell
            }
        }
        return Capability.allCases.map { capability in
            let cell = cells[capability] ?? ([], [], [])
            let state = cellState(wide: cell.wide, own: cell.own, narrow: cell.narrow)
            return CapabilityCell(capability: capability, label: capability.label, state: state, editable: state != .mixed, rules: cell.wide + cell.own + cell.narrow)
        }
    }
}
