import ReinsCore
import SwiftUI

/// One agent's card (spec, Interface: Page): the 40 pt CLI mark, the name, one sentence at Global (warn when risky), the
/// config root on the right, and a card button per panel, Advanced last as a ghost.
struct AgentCard: View {
    let agent: AgentKind
    let overview: AgentsOverview
    let openPanel: AgentPanel?
    let toggle: (AgentPanel) -> Void

    var body: some View {
        let sentence = agent == .claude ? AgentsWording.claudeSentence(overview.claude) : AgentsWording.codexSentence(overview.codex)
        ContentCard {
            VStack(alignment: .leading, spacing: Space.s16) {
                HStack(alignment: .center, spacing: Space.s16) {
                    CLIMark(agent.cli)
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(agent.name).reinsText(.title, tone: .primary).accessibilityAddTraits(.isHeader)
                        Text(sentence.text).reinsText(.body, tone: sentence.warn ? .warn : .secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(agent.root).reinsText(.code, tone: .tertiary)
                }
                FlowRow {
                    ForEach(AgentPanel.allCases) { panel in
                        CardButton(panel.title, icon: panel.icon, value: value(panel), kind: panel == .advanced ? .ghost : .plain,
                                   isOpen: openPanel == panel) { toggle(panel) }
                    }
                }
            }
        }
    }

    private func value(_ panel: AgentPanel) -> CardButtonValue? {
        switch (agent, panel) {
        case (.claude, .rules): return .code("CLAUDE.md")
        case (.codex, .rules): return .code("AGENTS.md")
        case (.claude, .permissions): return .count("\(overview.claude.allow.count + overview.claude.ask.count + overview.claude.deny.count)")
        case (.codex, .permissions): return AgentsWording.codexPermissionsValue(overview.codex)
        case (.claude, .hooks):
            let hooks = overview.hooks(.claude)
            return AgentsWording.hooksValue(total: hooks.count, dead: hooks.filter(\.dead).count)
        case (.codex, .hooks):
            let hooks = overview.hooks(.codex)
            return AgentsWording.hooksValue(total: hooks.count, dead: hooks.filter(\.dead).count)
        case (.claude, .mcp): return .count("\(overview.claudeMCP)")
        case (.codex, .mcp): return .count("\(overview.codex.mcpServers.count)")
        case (.claude, .model): return .code(overview.claude.model ?? "default")
        case (.codex, .model): return .code(overview.codex.model ?? "default")
        case (_, .advanced): return nil
        }
    }
}
