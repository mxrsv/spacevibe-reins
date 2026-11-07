import Observation
import SwiftUI

/// The Agents page (V5-R49): one sidebar page holding the tabs Skills, Subagents, Hooks and Rules. It owns the models the
/// tabs read (`LoadoutModel` for the first three, `RulesModel`), so the sidebar's count and each tab's count come from real reads
/// on every tab. Building it reads nothing; the page's first appearance starts the reads.
@MainActor
@Observable
final class AgentsPage: SpaceVibeTab {
    let id = TabRegistry.agentsID
    let title = "Agents"
    let glyph: any GlyphSource = ContentGlyph.stack
    let loadout: LoadoutModel
    let rules: RulesModel
    let skills: SkillsModel
    let subagents: SubagentsModel
    let hooks: HooksModel

    private(set) var selected = AgentsCategory.skills

    init(env: AppEnvironment? = nil, loadout: LoadoutModel? = nil, rules: RulesModel? = nil) {
        let env = env ?? .shared
        self.loadout = loadout ?? LoadoutModel(env: env)
        self.rules = rules ?? RulesModel(env: env)
        skills = SkillsModel(loadout: self.loadout)
        subagents = SubagentsModel(loadout: self.loadout)
        hooks = HooksModel(loadout: self.loadout)
    }

    var counts: AgentsCounts { AgentsCounts(loadout: loadout.data, rules: rules.badge) }

    /// The total of skills, subagents and hooks.
    var badge: TabBadge? {
        counts.total.map { TabBadge(value: $0, spoken: "\($0) \($0 == 1 ? "item" : "items")") }
    }

    /// The status bar's keys and data source follow the selected tab; a tab not built yet lists none.
    var hints: [KeyHint] {
        switch selected {
        case .skills: SkillsStatusBar.hints
        case .subagents: SubagentsStatusBar.hints
        case .hooks: HooksStatusBar.hints
        case .rules: RulesStatusBar.hints
        }
    }

    var source: String? {
        switch selected {
        case .skills: SkillsStatusBar.source
        case .subagents: SubagentsStatusBar.source
        case .hooks: HooksStatusBar.source
        case .rules: RulesStatusBar.source
        }
    }

    /// A head menu of the selected tab holds the keyboard, so the page's plain keys (`1` to `4`) are off.
    var isMenuOpen: Bool {
        switch selected {
        case .skills: skills.isMenuOpen
        case .subagents: subagents.isMenuOpen
        case .hooks: hooks.isMenuOpen
        case .rules: rules.isMenuOpen
        }
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

/// The tab head with its four tabs, then the selected tab's chip row and canvas: Skills (U8), Subagents (U9), Hooks (U10) and Rules (U11).
struct AgentsPageView: View {
    let page: AgentsPage

    @Environment(ShellModel.self) private var shell

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !shell.isPaletteOpen && !page.isMenuOpen { tabKeys }
            VStack(spacing: 0) {
                TabHead {
                    ForEach(AgentsCategory.allCases) { category in
                        TabChip(
                            title: category.title, glyph: category.glyph, count: page.counts.count(for: category), tone: category.tone,
                            isActive: page.selected == category
                        ) { page.select(category) }
                    }
                } actions: {
                    switch page.selected {
                    case .skills: SkillsHeadActions(model: page.skills)
                    case .subagents: SubagentsHeadActions(model: page.subagents)
                    case .hooks: HooksHeadActions(model: page.hooks)
                    case .rules: RulesHeadActions(model: page.rules)
                    }
                }
                switch page.selected {
                case .skills:
                    if page.skills.query.filter.isOn { SkillsChipRow(model: page.skills) }
                    SkillsCanvas(model: page.skills)
                case .subagents:
                    if page.subagents.query.filter.isOn { SubagentsChipRow(model: page.subagents) }
                    SubagentsCanvas(model: page.subagents)
                case .hooks:
                    if page.hooks.query.filter.isOn { HooksChipRow(model: page.hooks) }
                    HooksCanvas(model: page.hooks)
                case .rules:
                    if page.rules.filter.isOn { RulesChipRow(model: page.rules) }
                    RulesCanvas(model: page.rules)
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
