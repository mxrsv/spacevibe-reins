import SwiftUI

/// The bottom bar of a multi-select (V5-R32, V5-R26): 44 high on `bgPop` with a `hair2` edge, radius 8, the top-edge
/// highlight and the pop shadow, padding 0 8 0 16, parts 8 apart. It holds the count ("3 selected", 13/20 500), the strip's
/// label ("Add to", 12 pt `fg3`), the logo strip acting on every picked item, a `hair2` line, then 28-high buttons
/// (`Remove`, `Clear`) with their key caps. The page shows it while a row is picked, centred 48 above the panel's bottom,
/// and moves the toast up to 104. The strip's logos are the page's: lit when every picked item has that CLI (a mixed
/// selection shows the dim, press-to-add logo).
struct BulkBar<Strip: View, Actions: View>: View {
    let title: String
    var stripLabel: String
    @ViewBuilder var strip: Strip
    @ViewBuilder var actions: Actions

    init(_ title: String, stripLabel: String, @ViewBuilder strip: () -> Strip, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.stripLabel = stripLabel
        self.strip = strip()
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: Metrics.BottomBar.spacing) {
            Text(title)
                .spaceVibeText(.control, tone: .primary)
                .padding(.trailing, Metrics.BottomBar.countTrailing)
            Text(stripLabel)
                .spaceVibeText(.meta, tone: .tertiary)
                .padding(.leading, Metrics.BottomBar.labelLeading)
            strip
            Rectangle()
                .fill(Palette.hair2)
                .frame(width: Metrics.Radius.edge, height: Metrics.BottomBar.separatorHeight)
                .padding(.horizontal, Metrics.BottomBar.separatorInset)
                .accessibilityHidden(true)
            HStack(spacing: Metrics.BottomBar.spacing) { actions }
                .buttonStyle(ActionButtonStyle(size: .bar))
        }
        .lineLimit(1)
        .padding(.leading, Metrics.BottomBar.leading)
        .padding(.trailing, Metrics.BottomBar.trailing)
        .frame(height: Metrics.BottomBar.height)
        .blockSurface(Palette.bgPop, edge: Palette.hair2)
        .overlayShadow(.pop)
        .environment(\.logoRing, Palette.bgPop)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
