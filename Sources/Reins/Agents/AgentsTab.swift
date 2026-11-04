import ReinsCore
import SwiftUI

/// Registers Agents with the shell behind the development switch (`AgentsSwitch`): sidebar item, hints, palette entries
/// and the screen. Building it reads nothing; the screen's first appearance starts the read.
@MainActor
final class AgentsTab: ReinsTab {
    static let tabID = "agents"

    let id = AgentsTab.tabID
    let title = "Agents"
    let icon = ReinsGlyph.agent
    let pageIcon = PageGlyph.agent
    let model: AgentsModel

    init(env: AppEnvironment? = nil) { model = AgentsModel(env: env ?? .shared) }

    init(model: AgentsModel) { self.model = model }

    /// With the panel closed: Tab and Return; with it open: Esc, and `⌘S` while a draft exists (spec, Interface: Hint bar).
    var hints: [KeyHint] {
        AgentsWording.hints(panelOpen: model.open != nil, hasDraft: !model.draft.isEmpty).map { KeyHint(keys: $0.keys, label: $0.label) }
    }

    /// One entry per agent and panel: "Claude Code: Permissions".
    var paletteActions: [PaletteEntry] {
        AgentKind.allCases.flatMap { agent in
            AgentPanel.allCases.map { panel in
                PaletteEntry(id: "agents.\(agent.rawValue).\(panel.rawValue)", title: "\(agent.name): \(panel.title)", icon: panel.icon,
                             keywords: ["agent", "settings", agent.rawValue]) { [weak self] in
                    guard let self, self.model.open != OpenPanel(agent: agent, panel: panel) else { return }
                    self.model.toggle(OpenPanel(agent: agent, panel: panel))
                }
            }
        }
    }

    var content: AnyView { AnyView(AgentsScreen(model: model)) }
}
