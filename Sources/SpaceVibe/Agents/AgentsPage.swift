import AppKit
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

    /// A refresh that is not forced is skipped when the last one ran less than this long ago, so app activation, a return to the
    /// tab and a burst of both read once.
    static let refreshInterval: TimeInterval = 10

    private(set) var selected = AgentsCategory.skills
    @ObservationIgnored private var lastRefresh: Date?

    init(env: AppEnvironment? = nil, loadout: LoadoutModel? = nil, rules: RulesModel? = nil) {
        let env = env ?? .shared
        self.loadout = loadout ?? LoadoutModel(env: env)
        self.rules = rules ?? RulesModel(env: env)
        skills = SkillsModel(loadout: self.loadout)
        subagents = SubagentsModel(loadout: self.loadout)
        hooks = HooksModel(loadout: self.loadout)
    }

    /// The core's sentence when the inventory could not be read at all and nothing is shown yet; the pages then offer `Try again`
    /// instead of a skeleton that never ends (V5-A17).
    var readFailure: String? { loadout.data == nil ? loadout.readFailure : nil }

    /// The core's sentence when the usage scan failed and the rows still have no counts: the three tabs then say so and offer
    /// `Try again` (V5-A17), instead of cells that read "counting" for good.
    var scanFailure: String? { loadout.data != nil && loadout.usageResult == nil ? loadout.scanFailure : nil }

    var counts: AgentsCounts { AgentsCounts(loadout: loadout.data, rules: rules.badge) }

    /// The total of skills, subagents and hooks.
    var badge: TabBadge? {
        counts.total.map { TabBadge(value: $0, spoken: Self.spokenTotal($0)) }
    }

    /// What VoiceOver says after "Agents": the three kinds the total counts, never a generic "items" (V5-R45).
    static func spokenTotal(_ total: Int) -> String {
        total == 1 ? "1 skill, subagent or hook" : "\(total) skills, subagents and hooks"
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
        // The counts rest on the scan: once there is a result the bar says how many sessions and since when (GI6).
        case .skills: loadout.usageResult == nil ? SkillsStatusBar.source : loadout.usageNote
        case .subagents: loadout.usageResult == nil ? SubagentsStatusBar.source : loadout.usageNote
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

    /// Reads the inventory, the usage and the rules again: files may have changed outside the app. A page that has not started
    /// reads nothing. Skipped inside `refreshInterval` of the last refresh unless `force` (`⌘R` and the palette force it).
    func refresh(force: Bool = false, now: Date = Date()) {
        if !force, let last = lastRefresh, now.timeIntervalSince(last) < Self.refreshInterval { return }
        lastRefresh = now
        loadout.refresh()
        rules.refresh()
    }

    var paletteActions: [PaletteEntry] {
        [PaletteEntry(id: "agents.refresh", title: "Refresh", glyph: ContentGlyph.enter, trailing: "⌘R", keywords: ["reload", "read again", "skills", "subagents", "hooks", "rules"]) { [weak self] in
            self?.refresh(force: true)
        }]
    }
}

/// The tab head with its four tabs, then the selected tab's chip row and canvas: Skills (U8), Subagents (U9), Hooks (U10) and Rules (U11).
struct AgentsPageView: View {
    let page: AgentsPage

    @Environment(ShellModel.self) private var shell

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !shell.isPaletteOpen && !page.isMenuOpen {
                tabKeys
                HiddenKey(KeyboardShortcut("r", modifiers: .command)) { page.refresh(force: true) }
            }
            VStack(spacing: 0) {
                TabHead {
                    ForEach(AgentsCategory.allCases) { category in
                        TabChip(
                            title: category.title, glyph: category.glyph, count: page.counts.count(for: category), tone: category.tone,
                            isActive: page.selected == category
                        ) { page.select(category) }
                    }
                } actions: {
                    scanFailureSlot
                    switch page.selected {
                    case .skills: SkillsHeadActions(model: page.skills)
                    case .subagents: SubagentsHeadActions(model: page.subagents)
                    case .hooks: HooksHeadActions(model: page.hooks)
                    case .rules: RulesHeadActions(model: page.rules)
                    }
                }
                canvas
            }
        }
        .task { page.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in page.refresh() }
        .onChange(of: shell.activeID) { _, id in if id == page.id { page.refresh() } }
    }

    /// The warning glyph at the head's left of the actions: what failed in the core's words and `Try again` beside it.
    @ViewBuilder
    private var scanFailureSlot: some View {
        if let failure = page.scanFailure, page.selected != .rules {
            WarningSlot(mark: StateMark(.warn, label: "Usage could not be counted"), detail: failure, id: "agents:scan") {
                PopoverSentence("Usage could not be counted, so the counts are missing. \(failure)")
                PopoverActions { Button { page.loadout.retry() } label: { ActionLabel("Try again") } }
            }
        }
    }

    /// The selected tab's chip row and canvas; a failed read of the inventory replaces the three tabs that depend on it.
    @ViewBuilder
    private var canvas: some View {
        if let failure = page.readFailure, page.selected != .rules {
            QuietEmptyState("Could not read your CLI folders", message: failure, placement: .list) {
                Button(action: page.loadout.retry) { ActionLabel("Try again") }.buttonStyle(ActionButtonStyle())
            }
            Spacer(minLength: 0)
        } else {
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

    /// `1` to `4` switch the tabs (V5-R36); a plain key, so off while the palette or a menu has the keyboard.
    private var tabKeys: some View {
        Group {
            ForEach(Array(AgentsCategory.allCases.enumerated()), id: \.element) { index, _ in
                HiddenKey(KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])) { page.select(index: index) }
            }
        }
    }
}
