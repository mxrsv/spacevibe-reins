import SwiftUI

/// Three tabs with made-up content and counts, built only from the shared views. They stand in for the real
/// screens in screenshots so the shell is judged with realistic rows. Never registered in `TabRegistry`.
@MainActor
enum DemoTabs {
    static func make() -> [any SpaceVibeTab] { [DemoLoadoutTab(), DemoRulesTab(), DemoActivityTab()] }
}

@MainActor
final class DemoLoadoutTab: SpaceVibeTab {
    let id = "loadout"
    let title = "Loadout"
    let icon = SpaceVibeGlyph.loadout
    var badge: TabBadge? { TabBadge(value: 22) }
    var hints: [KeyHint] { [KeyHint(keys: "Tab", label: "Row actions")] }
    var paletteItems: [PaletteEntry] {
        ["ponytail", "impeccable", "review-change", "skill-creator"].map { name in
            PaletteEntry(id: "demo.skill.\(name)", title: name, icon: .skill, keywords: ["skill"]) {}
        }
    }
    var paletteActions: [PaletteEntry] {
        [PaletteEntry(id: "demo.rescan", title: "Rescan usage", icon: .refresh) {}]
    }
    var content: AnyView { AnyView(DemoLoadoutScreen()) }
}

@MainActor
final class DemoRulesTab: SpaceVibeTab {
    let id = "rules"
    let title = "Rules"
    let icon = SpaceVibeGlyph.rules
    var badge: TabBadge? { TabBadge(value: 11) }
    var hints: [KeyHint] { [KeyHint(keys: "Space", label: "Set Allow, Ask or Deny")] }
    var content: AnyView { AnyView(DemoRulesScreen()) }
}

@MainActor
final class DemoActivityTab: SpaceVibeTab {
    let id = "activity"
    let title = "Activity"
    let icon = SpaceVibeGlyph.activity
    var badge: TabBadge? { TabBadge(value: 2, alert: true, spoken: "2 sessions running") }
    var hints: [KeyHint] { [KeyHint(keys: "Tab", label: "Why a state is what it is")] }
    var content: AnyView { AnyView(DemoActivityScreen()) }
}

private struct DemoLoadoutScreen: View {
    @State private var filter = "all"

    var body: some View {
        PageLayout {
            HStack(spacing: Rhythm.chips) {
                FilterChip("All", count: 22, isOn: filter == "all") { filter = "all" }
                FilterChip("In one CLI only", count: 16, isOn: filter == "one") { filter = "one" }
                FilterChip("Never ran", count: 5, isOn: filter == "never") { filter = "never" }
                FilterChip("Dead", count: 2, isOn: filter == "dead") { filter = "dead" }
            }
        } content: {
            DemoLoadoutList()
        }
    }
}

private struct DemoRulesScreen: View {
    @State private var scope = "global"
    @State private var push = "ask"
    private let column = Metrics.usageCellWidth + Metrics.usageCellWidth / 2

    var body: some View {
        PageLayout {
            SegmentedControl(label: "Scope", options: [
                SegmentOption("Global", value: "global"),
                SegmentOption("Project", value: "project", count: 3),
            ], selection: $scope)
        } content: {
            GroupedList {
                CardHeader("What the agent may do", columns: {
                    CLIColumnHead(.claude, width: column)
                    CLIColumnHead(.codex, width: column)
                })
                ForEach(["Read files", "Edit files", "Run commands"], id: \.self) { name in
                    Row { RowText(name) }
                        .lead { Chevron(.right, size: .row) }
                        .cells {
                            SegmentedControl(label: "\(name), Claude Code", options: [
                                SegmentOption("Allow", value: "allow"),
                                SegmentOption("Ask", value: "ask"),
                                SegmentOption("Deny", value: "deny"),
                            ], selection: .constant("allow"))
                            .frame(width: column, alignment: .leading)
                            Text("no setting").spaceVibeText(.body, tone: .tertiary)
                                .frame(width: column, alignment: .leading)
                        }
                }
                Row { RowText("Push and deploy") }
                    .lead { Chevron(.right, size: .row) }
                    .cells {
                        SegmentedControl(label: "Push and deploy, Claude Code", options: [
                            SegmentOption("Allow", value: "allow"),
                            SegmentOption("Ask", value: "ask"),
                            SegmentOption("Deny", value: "deny"),
                        ], selection: $push)
                        .frame(width: column, alignment: .leading)
                        Tag("workspace only", tone: .neutral)
                            .frame(width: column, alignment: .leading)
                    }
            }
        }
    }
}

private struct DemoActivityScreen: View {
    var body: some View {
        PageLayout {
            VStack(alignment: .leading, spacing: Rhythm.regions) {
                Banner(.warn, message: "Codex does not record permission prompts", detail: "A long command and a wait for approval look the same.")
                GroupedList {
                    CardHeader("Running", count: 2, lead: { CLIDot(.claude, decorative: true) })
                    Row { RowText("Fix leaderboard rank tie", subtitle: "demo-bench \u{00B7} Bash \u{00B7} 18 min") }
                        .lead { CLIDot(.claude) }
                        .cells { StateCell { Tag("running", tone: .success) }; NumberCell(text: "~$0.89") }
                    Row { RowText("Add cache header", subtitle: "demo-api \u{00B7} 9 min") }
                        .lead { CLIDot(.codex) }
                        .cells { StateCell { Tag("running", tone: .success) }; NumberCell(text: "~$4.80") }
                    EmptyRow("No failed commands in the last 14 days.")
                }
            }
        }
    }
}
