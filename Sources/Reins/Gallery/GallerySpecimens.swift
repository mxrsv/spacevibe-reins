import ReinsCore
import SwiftUI

/// The ruler at the usage cell's width (its number column beside it) and at a wider track: the cell is a tenth of the
/// track either way. Inside a card, where it always sits.
struct RulerSpecimens: View {
    private let shares: [(String, Double?, LimitTone)] = [
        ("0%", 0, .normal), ("4%", 0.04, .normal), ("39%", 0.39, .normal), ("100%", 1, .normal),
        ("not known", nil, .normal), ("20% left", 0.2, .low), ("5% left", 0.05, .out),
    ]

    var body: some View {
        GroupedList {
            CardHeader("Ruler", count: shares.count, columns: {
                Text("at the usage cell's track").frame(width: Metrics.usageCellWidth, alignment: .leading)
                Text("at twice that").frame(width: Metrics.usageCellWidth * 2, alignment: .leading)
            })
            ForEach(shares, id: \.0) { label, share, tone in
                Row { RowText(label) }
                    .cells {
                        HStack(spacing: Metrics.rowSpacing) {
                            Ruler(share: share, fill: tone.barFill ?? Palette.claude)
                            Text(label).reinsText(.number, tone: .secondary).frame(width: Metrics.usageNumberWidth, alignment: .trailing)
                        }
                        .frame(width: Metrics.usageCellWidth)
                        Ruler(share: share, fill: tone.barFill ?? Palette.codex).frame(width: Metrics.usageCellWidth * 2)
                    }
            }
        }
    }
}

/// The Limits page's parts in every state, on the page well: window tiles (selected, low, out, passed, not in use, no
/// reading), the figure in each tone and unknown, the detail ruler and facts in a card, and the sidebar's tiles.
struct LimitsSpecimens: View {
    var body: some View {
        HStack(alignment: .top, spacing: Rhythm.listDetail) {
            VStack(spacing: Rhythm.tiles) {
                LimitWindowTile(cli: .codex, title: "Weekly", subtitle: "Codex \u{00B7} resets in 1 d 3 h",
                                meter: .share(0.04, fill: Palette.danger), value: "4%", valueTone: .danger, selected: true, onActivate: {})
                LimitWindowTile(cli: .codex, title: "5-hour", subtitle: "Codex \u{00B7} reset passed", meter: .unknown,
                                value: "unknown", onActivate: {})
                LimitWindowTile(cli: .claude, title: "Weekly", subtitle: "Claude Code \u{00B7} resets in 2 d 22 h",
                                meter: .share(0.18, fill: Palette.warn), value: "18%", valueTone: .warn, onActivate: {})
                LimitWindowTile(cli: .claude, title: "Weekly \u{00B7} Fable", subtitle: "Claude Code \u{00B7} resets in 2 d 22 h",
                                meter: .share(0.92, fill: Palette.claude), value: "92%", onActivate: {}) { Tag("not in use") }
                LimitWindowTile(cli: .gemini, title: "Gemini CLI", subtitle: "Not measurable", meter: .none, value: "\u{2014}", onActivate: {})
            }
            .frame(width: Metrics.limitsListWidth)
            VStack(alignment: .leading, spacing: Rhythm.cards) {
                ContentCard {
                    VStack(alignment: .leading, spacing: Space.s16) {
                        LimitFigure(left: 92)
                        LimitFigure(left: 18, tone: .low)
                        LimitFigure(left: 4, tone: .out)
                        LimitFigure(left: nil)
                        Ruler(share: 0.04, fill: Palette.danger, height: Metrics.rulerDetailHeight)
                        Ruler(share: nil, fill: Palette.codex, height: Metrics.rulerDetailHeight)
                        HStack(alignment: .top, spacing: Rhythm.tiles) {
                            FactTile("Resets in", value: "1 d 3 h")
                            FactTile("Reset at", value: "17:34")
                            FactTile("Reading", value: "2 days ago", tone: .warn)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(spacing: Space.s6) {
                    LimitSidebarTile(cli: .claude, name: "Claude Code", value: "92% left")
                    LimitSidebarTile(cli: .codex, name: "Codex", value: "18% left", tone: .low)
                    LimitSidebarTile(cli: .codex, name: "Codex", value: "4% left", tone: .out)
                    LimitSidebarTile(cli: .gemini, name: "Gemini CLI", value: "not measurable", isMuted: true)
                }
                .padding(Space.s8)
                .frame(width: Metrics.sidebarWidth)
                .background(Palette.well)
            }
        }
    }
}

/// The Settings pieces in each state: the rail on the well, then the tiles, switches, mark and raised block in a card.
struct SettingsSpecimens: View {
    @State private var section = SettingsSection.appearance
    @State private var theme = ThemeSetting.dark
    @State private var on = true
    @State private var off = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(spacing: Space.s4) {
                ForEach(SettingsSection.allCases) { item in
                    RailTab(title: item.title, icon: item.icon, isActive: item == section) { section = item }
                }
            }
            GroupedList {
                HStack(spacing: Rhythm.tiles) {
                    ForEach(ThemeSetting.allCases, id: \.self) { item in
                        ThemeTile(title: item.title, icon: item.icon, appearance: item.fixed?.colorScheme, isSelected: item == theme) { theme = item }
                    }
                }
                .frame(width: Metrics.settingsColumnWidth)
                .padding(.horizontal, Metrics.rowInset)
                .padding(.top, Space.s8)
                .groupedListPart(.plain)
                HStack(spacing: Space.s16) {
                    ReinsSwitch(label: "On", isOn: $on)
                    ReinsSwitch(label: "Off", isOn: $off)
                    ReinsSwitch(label: "Disabled", isOn: .constant(false)).disabled(true)
                    ReinsMark()
                    RaisedBlock { Text("A raised block inside a card").reinsText(.body, tone: .secondary) }
                        .frame(width: Metrics.usageCellWidth * 2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.rowHorizontalPadding)
                .padding(.top, Space.s8)
                .groupedListPart(.plain)
            }
        }
    }
}
