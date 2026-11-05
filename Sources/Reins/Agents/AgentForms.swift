import Foundation
import Observation
import ReinsCore

/// What the panels' add rows and fields hold before they become draft items. Reset when the panel, the scope or the draft
/// changes.
@MainActor
@Observable
final class AgentForms {
    var rule = ""
    var verdict = RuleVerdict.ask
    var ruleError: String?
    var folder = ""
    var hookEvent = "PreToolUse"
    var hookMatcher = ""
    var hookCommand = ""
    var serverName = ""
    var serverKind = MCPServer.Kind.command
    var serverTarget = ""
    var expandedServers: Set<String> = []
    /// The secret being replaced, and its new value (never the old one).
    var replacing: (server: String, secret: MCPSecretName)?
    var secretValue = ""
    var model = ""
    var commandRule = ""
    var decision = "prompt"
    var path = ""
    var pathAccess = "read"
    var domain = ""
    var domainAccess = "allow"
    var root = ""

    func reset() {
        rule = ""; ruleError = nil; folder = ""; hookMatcher = ""; hookCommand = ""
        serverName = ""; serverTarget = ""; replacing = nil; secretValue = ""; model = ""
        commandRule = ""; path = ""; domain = ""; root = ""
    }
}

/// The review dialog's words (spec, Draft and save): the journal label, the lines, the files, the copy note and the warn
/// notes for risky values. Pure, so the tests pin it.
enum AgentsReview {
    static let copyNote = "Reins keeps a copy you can restore."

    static func label(_ draft: AgentDraft, _ context: AgentsSavePlan.Context) -> String {
        let what = draft.count == 1 ? (draft.items.first.map { "\($0.verb.rawValue) \($0.text)" } ?? "") : "\(draft.count) changes"
        return "\(context.agent.name) \(context.panel.title): \(what)"
    }

    static func title(_ draft: AgentDraft, _ context: AgentsSavePlan.Context) -> String {
        "Save \(AgentsWording.plural(draft.count, "change")) to \(context.agent.name) \(context.panel.title)?"
    }

    static func scopeLine(_ context: AgentsSavePlan.Context) -> String {
        "Scope: \(AgentsWording.scopeTitle(context.scope))"
    }

    static func warnings(_ draft: AgentDraft) -> [String] {
        var out: [String] = []
        for item in draft.items { if let warning = item.warning, !out.contains(warning) { out.append(warning) } }
        return out
    }
}
