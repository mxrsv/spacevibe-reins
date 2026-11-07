import SwiftUI

/// A pill that filters a list, 28 pt high like every control, with no outline: the control ground's fill, or the `selection`
/// tint while on. Several chips side by side act as one single-choice filter; the caller owns the state. `count` is how many
/// rows the filter would show.
///
/// The dismissible form is an applied scope ("spacevibe-bench ×"): always on, and only the × acts. The × is its own
/// button with a spoken label, so a keyboard user reaches it directly.
struct FilterChip: View {
    let title: String
    var count: Int?
    let isOn: Bool
    let action: () -> Void
    var onDismiss: (() -> Void)?
    @Environment(\.controlGround) private var ground

    init(_ title: String, count: Int? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isOn = isOn
        self.action = action
    }

    /// An applied scope that the × clears.
    init(dismissible title: String, onDismiss: @escaping () -> Void) {
        self.title = title
        isOn = true
        action = {}
        self.onDismiss = onDismiss
    }

    var body: some View {
        if let onDismiss {
            pill(trailing: Space.s8) {
                Text(title)
                Button(action: onDismiss) {
                    SpaceVibeIcon(.close).foregroundStyle(TextTone.secondary.color)
                }
                .buttonStyle(.plain)
                .spaceVibeFocusable(cornerRadius: Metrics.segmentRadius)
                .help("Clear \(title)")
                .accessibilityLabel("Clear \(title)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Button(action: action) {
                pill(trailing: Space.s12) {
                    Text(title)
                    if let count { Count(count) }
                }
            }
            .buttonStyle(.plain)
            .spaceVibeFocusable(cornerRadius: Metrics.chipHeight / 2)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
            .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
            .accessibilityHint("Filter")
        }
    }

    private func pill<Content: View>(trailing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Space.s6) { content() }
            .spaceVibeText(.body, tone: isOn ? .primary : .secondary)
            .padding(.leading, Space.s12)
            .padding(.trailing, trailing)
            .frame(height: Metrics.chipHeight)
            .background(Capsule().fill(isOn ? Palette.selection : ground.fill))
            .contentShape(Capsule())
    }
}

/// One applied filter in the v5 chip row (V5-R28): `field | value | x`, 24 high, radius 6, `bgRaise` with a `hair2` edge
/// and `hair` lines between the parts. The field reads in `fg2`, the value in `fg`, both 12 pt; the close button is 24 wide
/// with a 12 pt glyph in `fg3`, hovered `hover` and `fg`, focused `sel`. The capsule `FilterChip` above stays for the old
/// screens until the cut-over (X1).
struct FilterFieldChip: View {
    let field: String
    let value: String
    let onRemove: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        HStack(spacing: 0) {
            Text(field).foregroundStyle(Palette.fg2).padding(.horizontal, Metrics.FilterChipRow.partPadding)
            ChipDivider()
            Text(value).foregroundStyle(Palette.fg).padding(.horizontal, Metrics.FilterChipRow.partPadding)
            ChipDivider()
            Button(action: onRemove) {
                SpaceVibeIcon(content: .close, size: .small)
                    .frame(width: Metrics.FilterChipRow.closeWidth, height: Metrics.FilterChipRow.chipHeight)
            }
            .buttonStyle(ChipPartStyle(rest: Palette.fg3))
            .focusEffectDisabled()
            .accessibilityLabel("Remove \(field) \(value)")
        }
        .spaceVibeText(.meta)
        .lineLimit(1)
        .frame(height: Metrics.FilterChipRow.chipHeight)
        .background(shape.fill(Palette.bgRaise))
        .overlay(shape.strokeBorder(Palette.hair2, lineWidth: Metrics.Radius.edge).allowsHitTesting(false))
        .clipShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(field) \(value)")
    }
}

/// A `hair` line between two parts of a chip.
private struct ChipDivider: View {
    var body: some View {
        Rectangle().fill(Palette.hair).frame(width: Metrics.Radius.edge).accessibilityHidden(true)
    }
}

/// A part of a chip that acts (the close button, `Clear`): hovered `hover` with `fg` text, focused `sel` (D57).
private struct ChipPartStyle: ButtonStyle {
    let rest: Color

    func makeBody(configuration: Configuration) -> some View { StyledLabel(configuration: configuration, rest: rest) }

    private struct StyledLabel: View {
        let configuration: ButtonStyle.Configuration
        let rest: Color
        @Environment(\.isFocused) private var isFocused
        @Environment(\.specimenInteraction) private var specimen
        @State private var hovering = false

        var body: some View {
            let hovered = hovering || specimen.contains(.hover)
            let focused = isFocused || specimen.contains(.focus) || configuration.isPressed
            configuration.label
                .foregroundStyle(hovered ? Palette.fg : rest)
                .background(focused ? Palette.sel : (hovered ? Palette.hover : .clear))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// The row of applied filters under the tab head (V5-R28): chips 8 apart, wrapping, padding 8 12, a `hair` line under it,
/// and `Clear` at the end (a 24-high chip in `fg2`). The page shows it only while a filter is on, except Activity, which
/// keeps it on every tab so filtered counts are explained (V5-R69).
struct FilterChipRow<Chips: View>: View {
    let onClear: () -> Void
    @ViewBuilder var chips: Chips

    var body: some View {
        ChipFlow(spacing: Metrics.FilterChipRow.spacing) {
            chips
            Button(action: onClear) {
                Text("Clear")
                    .spaceVibeText(.meta)
                    .padding(.horizontal, Metrics.FilterChipRow.partPadding)
                    .frame(height: Metrics.FilterChipRow.chipHeight)
            }
            .buttonStyle(ChipPartStyle(rest: Palette.fg2))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle))
            .focusEffectDisabled()
            .accessibilityLabel("Clear filters")
        }
        .padding(.vertical, Metrics.FilterChipRow.verticalPadding)
        .padding(.horizontal, Metrics.FilterChipRow.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hair).frame(height: Metrics.Radius.edge).accessibilityHidden(true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filters")
    }
}

/// Lays chips out left to right, `spacing` apart both ways, starting a new line when the next one does not fit (the kit's
/// `flex-wrap`).
private struct ChipFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, lines.count - 1))
        let used = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            if !line.indices.isEmpty && needed > width {
                lines.append(line)
                line = Line()
            }
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }
}
