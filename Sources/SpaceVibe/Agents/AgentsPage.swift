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
    let skills: SkillsModel

    private(set) var selected = AgentsCategory.skills

    init(env: AppEnvironment? = nil, loadout: LoadoutModel? = nil) {
        let env = env ?? .shared
        self.loadout = loadout ?? LoadoutModel(env: env)
        rules = RulesModel(env: env)
        skills = SkillsModel(loadout: self.loadout)
    }

    var counts: AgentsCounts { AgentsCounts(loadout: loadout.data, rules: rules.badge) }

    /// The total of skills, subagents and hooks.
    var badge: TabBadge? {
        counts.total.map { TabBadge(value: $0, spoken: "\($0) \($0 == 1 ? "item" : "items")") }
    }

    /// The status bar's keys and data source follow the selected tab; a tab not built yet lists none.
    var hints: [KeyHint] { selected == .skills ? SkillsStatusBar.hints : [] }
    var source: String? { selected == .skills ? SkillsStatusBar.source : nil }

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

/// The tab head with its four tabs, then the selected tab's chip row and canvas: Skills is built (U8); the others show
/// "Not built yet" until U9 to U11 replace them.
struct AgentsPageView: View {
    let page: AgentsPage

    @Environment(ShellModel.self) private var shell

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !shell.isPaletteOpen && !page.skills.isMenuOpen { tabKeys }
            VStack(spacing: 0) {
                TabHead {
                    ForEach(AgentsCategory.allCases) { category in
                        TabChip(
                            title: category.title, glyph: category.glyph, count: page.counts.count(for: category), tone: category.tone,
                            isActive: page.selected == category
                        ) { page.select(category) }
                    }
                } actions: {
                    if page.selected == .skills { SkillsHeadActions(model: page.skills) }
                }
                if page.selected == .skills && page.skills.query.filter.isOn { SkillsChipRow(model: page.skills) }
                if page.selected == .skills {
                    SkillsCanvas(model: page.skills)
                } else {
                    QuietEmptyState("Not built yet", message: "\(page.selected.title) arrives in a later step of the v5 build.", placement: .list)
                    Spacer(minLength: 0)
                }
            }
        }
        .task { page.start() }
    }

    /// `1` to `4` switch the tabs (V5-R36); a plain key, so off while the palette or a menu has the keyboard.
    private var tabKeys: some View {
        Group {
            ForEach(Array(AgentsCategory.allCases.enumerated()), id: \.element) { index, _ in
                HiddenKey(KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])) { page.select(index: index) }
            }
        }
    }
}
