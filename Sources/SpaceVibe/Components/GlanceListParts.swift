import SwiftUI

/// The glance widget's hover list (spec `docs/specs/2026-11-19-session-glance-widget.md`, GW4, GW-R5): `bgPop` with the
/// `hair2` edge and the window's corner, 5 inside its edge. 300 wide, or `width` when given (a short note hugs its text).
/// The window around it draws the drop shadow, so the surface is exactly the window's size.
struct GlanceListSurface<Content: View>: View {
    var width: CGFloat? = Metrics.Glance.listWidth
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(Metrics.Glance.listPadding)
            .frame(width: width, alignment: .leading)
            .blockSurface(Palette.bgPop, edge: Palette.hair2, radius: Metrics.Radius.window)
            .accessibilityElement(children: .contain)
    }
}

/// One live session in the hover list (GW4, GW-R5): the CLI logo (14) beside two lines, the title over a quiet detail (the
/// running tool, or why the state cannot be measured), and on the right the state glyph and its label. The hovered row fills
/// and shows where a click goes ("Ghostty", or "Activity" when no host app is found, GW5, GW6) under the state. `hint` is
/// asked only for the hovered row. The whole row takes the click.
struct GlanceSessionRow: View {
    let cli: CLIID
    let title: String
    let detail: String
    let state: GlanceState
    let stateLabel: String
    /// False while the widget is not on screen: the working ring stops.
    var isAnimating = true
    /// Where the click goes, read when the pointer rests on the row.
    let hint: () -> String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle)
        Button(action: action) {
            HStack(spacing: Metrics.Glance.rowColumnSpacing) {
                CLIMark(cli, size: .glyph)
                VStack(alignment: .leading, spacing: Metrics.Glance.rowLineSpacing) {
                    line(title, role: .metaLabel, tone: .primary)
                    line(detail, role: .small, tone: .tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: Metrics.Glance.rowLineSpacing) {
                    HStack(spacing: Metrics.Glance.stateSpacing) {
                        SessionStateGlyph(state: state, isAnimating: isAnimating)
                        line(stateLabel, role: .small, tone: .secondary)
                    }
                    .fixedSize()
                    hintLine
                }
            }
            .padding(Metrics.Glance.rowPadding)
            .background(shape.fill(hovering ? Palette.sel : Color.clear))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cli.label), \(title), \(stateLabel)")
        .accessibilityValue(detail)
        .accessibilityAddTraits(.isButton)
    }

    /// The hovered row's destination, or an empty line of the same height so no row changes size on hover.
    @ViewBuilder
    private var hintLine: some View {
        if hovering {
            HStack(spacing: Metrics.Glance.hintSpacing) {
                SpaceVibeIcon(content: .open, size: .small, ink: Palette.fg3)
                line(hint(), role: .small, tone: .tertiary)
            }
            .frame(maxWidth: Metrics.Glance.hintMaxWidth, alignment: .trailing)
        } else {
            line(" ", role: .small, tone: .tertiary)
        }
    }

    private func line(_ text: String, role: SpaceVibeType, tone: TextTone) -> some View {
        Text(text).spaceVibeText(role, tone: tone).lineLimit(1).truncationMode(.tail).lineBox(role)
    }
}

/// The list's one sentence when there is no row: "No session running" (GW-R4), or why the sessions could not be read. A
/// failure with rows still shown (the last read) puts it above them.
struct GlanceListNote: View {
    let text: String

    var body: some View {
        Text(text)
            .spaceVibeText(.meta, tone: .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .lineBox(.meta)
            .padding(Metrics.Glance.noteInsets)
    }
}
