import ReinsCore
import SwiftUI

/// Made-up Loadout cards that exercise every usage state. Synthetic names only; used by the gallery and the demo tabs,
/// never by a real screen.
struct DemoLoadoutList: View {
    var selectedName: String? = "impeccable"
    var note: String? = "Counted from 146 Claude Code and 34 Codex sessions since 2026-10-05"

    private struct Item {
        var name: String
        var subtitle: String
        var icon = ReinsGlyph.skill
        var claude: UsageCellModel
        var codex: UsageCellModel
        var tags: [(String, TagTone, ReinsGlyph?)] = []
        var codeSubtitle = false
        var removable: [InventoryCLI] = [.claude]
    }

    private let skills: [Item] = [
        Item(name: "ponytail", subtitle: "Counted in Claude Code, not installed in Codex", claude: .counted(runs: 142), codex: .missing),
        Item(name: "impeccable", subtitle: "Counted in both", claude: .counted(runs: 87), codex: .counted(runs: 31), removable: [.claude, .codex]),
        Item(name: "review-change", subtitle: "Installed, never ran", claude: .counted(runs: 0), codex: .missing),
        Item(name: "skill-creator", subtitle: "Added today, not counted yet", claude: .pending(reason: "Added after the last scan; counted on the next one."), codex: .missing, tags: [("added recently", .neutral, nil)]),
        Item(name: "neon-postgres", subtitle: "Owned by a plugin, read-only", claude: .counted(runs: 11), codex: .missing, tags: [("plugin: neon", .neutral, .lock)], removable: []),
    ]
    private let hooks: [Item] = [
        Item(name: "Stop", subtitle: "Codex does not log hook runs", icon: .hook, claude: .counted(runs: 203), codex: .unmeasurable(reason: "Codex does not log hook runs."), removable: [.claude, .codex]),
        Item(name: "PostToolUse \u{00B7} Edit|Write", subtitle: "prettier --write \"$FILE\"", icon: .hook, claude: .counted(runs: 12_345), codex: .missing, tags: [("17 errors", .warn, nil)], codeSubtitle: true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Rhythm.cards) {
            card("Skills", skills, max: 142)
            VStack(alignment: .leading, spacing: Rhythm.caption) {
                card("Hooks", hooks, max: 12_345)
                UsageLegend(note: note)
            }
        }
    }

    private func card(_ title: String, _ items: [Item], max: Int) -> some View {
        GroupedList {
            CardHeader(title, count: items.count, columns: {
                CLIColumnHead(.claude)
                CLIColumnHead(.codex)
                Color.clear.frame(width: Metrics.loadoutActionsWidth, height: 1)
            })
            ForEach(items, id: \.name) { row($0, max: max) }
        }
    }

    private func row(_ item: Item, max: Int) -> some View {
        Row(selected: item.name == selectedName, onActivate: {}) {
            RowText(item.name, subtitle: item.subtitle, codeSubtitle: item.codeSubtitle) {
                ForEach(item.tags, id: \.0) { tag in Tag(tag.0, tone: tag.1, icon: tag.2) }
            }
        }
        .lead { ReinsIcon(item.icon, size: .row) }
        .cells {
            UsageCell(cli: .claude, model: item.claude, max: max, onAdd: nil)
            UsageCell(cli: .codex, model: item.codex, max: max, onAdd: item.codex == .missing ? {} : nil)
        }
        .actions {
            HStack(spacing: Space.s4) {
                if item.removable.isEmpty {
                    Color.clear.frame(width: Metrics.controlHeight, height: 1)
                    ReinsIcon(.lock, label: "Owned by a plugin").foregroundStyle(Palette.textTertiary)
                        .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                } else {
                    ForEach(InventoryCLI.allCases, id: \.self) { cli in
                        if item.removable.contains(cli) {
                            RowActionButton(title: "Remove from \(cli.label)", icon: .trash, kind: .danger, iconOnly: true, badge: cli) {}
                        } else {
                            Color.clear.frame(width: Metrics.controlHeight, height: 1)
                        }
                    }
                }
            }
            .frame(width: Metrics.loadoutActionsWidth, alignment: .trailing)
        }
    }
}
