import Observation
import SwiftUI

/// The Agents page (V5-R49): one sidebar page holding the tabs Skills, Subagents, Hooks and Rules. It owns the models the
/// tabs read (`LoadoutModel` for the first three, `RulesModel`), so the sidebar's count and each tab's count come from real reads
/// even while a tab shows "Not built yet" (U8 to U11 replace each canvas). Building it reads nothing; the page's first
/// appearance starts the reads.
@MainActor
@Observable
final class AgentsPage: SpaceVibeTab {
    let id = TabRegistry.agentsID
    let title = "Agents"
    let glyph: any GlyphSource = ContentGlyph.stack
    let loadout: LoadoutModel
    let rules: RulesModel

    private(set) var selected = AgentsCategory.skills

    init(env: AppEnvironment? = nil) {
        let env = env ?? .shared
        loadout = LoadoutModel(env: env)
        rules = RulesModel(env: env)
    }

    var counts: AgentsCounts { AgentsCounts(loadout: loadout.data, rules: rules.badge) }

    /// The total of skills, subagents and hooks.
    var badge: TabBadge? {
        counts.total.map { TabBadge(value: $0, spoken: "\($0) \($0 == 1 ? "item" : "items")") }
    }

    var content: AnyView { AnyView(AgentsPageView(page: self)) }

    func select(_ category: AgentsCategory) { selected = category }

    /// `1` is index 0; an index outside the four tabs does nothing.
    func select(index: Int) {
        guard AgentsCategory.allCases.indices.contains(index) else { return }
        selected = AgentsCategory.allCases[index]
    }

    func start() {
        loadout.start()
        rules.start()
    }
}

/// The tab head with its four tabs, and "Not built yet" in the canvas of the selected one.
struct AgentsPageView: View {
    let page: AgentsPage

    var body: some View {
        VStack(spacing: 0) {
            TabHead {
                ForEach(AgentsCategory.allCases) { category in
                    TabChip(
                        title: category.title, glyph: category.glyph, count: page.counts.count(for: category), tone: category.tone,
                        isActive: page.selected == category
                    ) { page.select(category) }
                }
            } actions: {
            }
            QuietEmptyState("Not built yet", message: "\(page.selected.title) arrives in a later step of the v5 build.", placement: .list)
            Spacer(minLength: 0)
        }
        .task { page.start() }
    }
}
