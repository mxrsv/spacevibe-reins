import SwiftUI

/// Made-up Loadout rows that exercise every usage state. Synthetic names only; used by the gallery and the
/// demo tabs, never by a real screen.
struct DemoLoadoutList: View {
    var selectedName: String? = "impeccable"

    private struct Item {
        var name: String
        var subtitle: String
        var icon = "sparkles"
        var claude: UsageCellModel
        var codex: UsageCellModel
        var tags: [(String, TagTone, String?)] = []
        var mono = false
    }

    private let skills: [Item] = [
        Item(name: "ponytail", subtitle: "Counted in Claude Code, not installed in Codex", claude: .counted(runs: 142), codex: .missing),
        Item(name: "impeccable", subtitle: "Counted in both", claude: .counted(runs: 87), codex: .counted(runs: 31)),
        Item(name: "review-change", subtitle: "Installed, never ran", claude: .counted(runs: 0), codex: .missing, tags: [("never ran", .warn, nil)]),
        Item(name: "skill-creator", subtitle: "Added today, not counted yet", claude: .pending(reason: "Added after the last scan; counted on the next one."), codex: .missing),
        Item(name: "neon-postgres", subtitle: "Owned by a plugin, read-only", claude: .counted(runs: 11), codex: .missing, tags: [("plugin: neon", .neutral, "lock")]),
    ]
    private let hooks: [Item] = [
        Item(name: "Stop \u{00B7} notify-done.sh", subtitle: "Codex does not log hook runs", icon: "bolt", claude: .counted(runs: 203), codex: .unmeasurable(reason: "Codex does not log hook runs."), mono: true),
        Item(name: "PostToolUse \u{00B7} Edit|Write", subtitle: "prettier --write \"$FILE\"", icon: "bolt", claude: .counted(runs: 1204), codex: .missing, tags: [("17 errors", .warn, nil)], mono: true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupedList {
                HeadRow("Name") {
                    CLIColumnHead(.claude)
                    CLIColumnHead(.codex)
                }
                SectionRow("Skills", count: skills.count)
                ForEach(skills, id: \.name) { row($0) }
                SectionRow("Hooks", count: hooks.count)
                ForEach(hooks, id: \.name) { row($0) }
            }
            UsageLegend()
        }
    }

    private func row(_ item: Item) -> some View {
        let isSelected = item.name == selectedName
        return Row(selected: isSelected, onActivate: {}) {
            RowText(item.name, subtitle: item.subtitle, mono: item.mono) {
                ForEach(item.tags, id: \.0) { tag in Tag(tag.0, tone: tag.1, systemImage: tag.2) }
            }
        }
        .lead { Image(systemName: item.icon) }
        .cells {
            UsageCell(cli: .claude, model: item.claude, max: 203, onAdd: nil)
            UsageCell(cli: .codex, model: item.codex, max: 203, onAdd: item.codex == .missing ? {} : nil)
        }
        .actions {
            if item.tags.contains(where: { $0.2 == "lock" }) {
                Image(systemName: "lock").foregroundStyle(Palette.textTertiary).frame(width: Metrics.controlHeight, height: Metrics.controlHeight).accessibilityLabel("Owned by a plugin")
            } else {
                RowActionButton(title: "Remove \(item.name)", systemImage: "trash", kind: .danger, iconOnly: true) {}
            }
        }
    }
}
