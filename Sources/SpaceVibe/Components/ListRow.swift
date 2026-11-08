import SwiftUI

/// One row of a v5 list or card (V5-R22, V5-R23, V5-R56): an inset block 44 high with radius 8, holding in order an optional
/// lead slot (16, the grey category glyph, which becomes a checkbox on a pickable row when hovered, in multi-select and when
/// picked), optional cells before the name, the name (13, 450), and the cells after it (secondary text, bar, share, count,
/// the logo strip, the warning slot). Put rows in `ListRows`, which draws the dividers.
///
/// Fills, one at a time and never stacked (U2: two `sel` fills put `fg3` under 4.5:1): picked `accentBg`; current or focused
/// `sel`; hovered `hover`. The current row also has the 2 pt accent bar at its leading edge, 8 from the top and the bottom.
///
///     ListRow("5-hour", nameWidth: Metrics.limitsWindowName, isCurrent: true) { BarCell(share: 0.78); ShareCell(percent: 78) }
struct ListRow<Leading: View, Trailing: View>: View {
    let name: String
    var lead: (any GlyphSource)?
    /// A fixed name column, for rows where a cell takes the rest (a bar); otherwise the name takes the rest.
    var nameWidth: CGFloat?
    var isCurrent = false
    var isPicked = false
    /// Multi-select is on in this list: every pickable row shows its checkbox.
    var showsCheckboxes = false
    /// Makes the row pickable: the checkbox in the lead slot calls it.
    var onPick: (() -> Void)?
    /// A click, Return or Space on the row (it then takes keyboard focus).
    var onActivate: (() -> Void)?
    /// What VoiceOver reads for the row; the name when nil.
    var accessibilityName: String?
    let leading: Leading
    let trailing: Trailing

    @Environment(\.specimenInteraction) private var specimen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let hovered = hovering || specimen.contains(.hover)
        let isFocused = focused || specimen.contains(.focus)
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle)
        HStack(spacing: Metrics.ListRow.spacing) {
            if lead != nil || onPick != nil { leadSlot(hovered: hovered) }
            leading
            Text(name)
                .spaceVibeText(.rowName, tone: .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: nameWidth, alignment: .leading)
                .frame(maxWidth: nameWidth == nil ? .infinity : nil, alignment: .leading)
            trailing
        }
        .padding(.leading, Metrics.ListRow.leading)
        .padding(.trailing, Metrics.ListRow.trailing)
        .frame(height: Metrics.ListRow.height)
        .background(shape.fill(fill(hovered: hovered, focused: isFocused)))
        .overlay(alignment: .leading) {
            if isCurrent {
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: Metrics.ListRow.currentBarWidth)
                    .padding(.vertical, Metrics.ListRow.currentBarInset)
            }
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .modifier(RowActivation(onActivate: onActivate, focused: $focused))
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName ?? name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .containerValue(\.listRowFilled, isPicked || isCurrent || isFocused || hovered)
    }

    private func fill(hovered: Bool, focused: Bool) -> Color {
        if isPicked { return Palette.accentBg }
        if isCurrent || focused { return Palette.sel }
        if hovered { return Palette.hover }
        return .clear
    }

    private func leadSlot(hovered: Bool) -> some View {
        let checkbox = onPick != nil && (hovered || showsCheckboxes || isPicked)
        return ZStack {
            if checkbox, let onPick {
                RowCheckbox(name: name, isPicked: isPicked, onPick: onPick)
            } else if let lead {
                SpaceVibeIcon(source: lead, size: .control, ink: Palette.fg3)
            }
        }
        .frame(width: Metrics.ListRow.checkbox, height: Metrics.ListRow.checkbox)
    }
}

extension ListRow where Leading == EmptyView, Trailing == EmptyView {
    init(_ name: String, lead: (any GlyphSource)? = nil, nameWidth: CGFloat? = nil, isCurrent: Bool = false, isPicked: Bool = false,
         showsCheckboxes: Bool = false, onPick: (() -> Void)? = nil, onActivate: (() -> Void)? = nil, accessibilityName: String? = nil) {
        self.init(name: name, lead: lead, nameWidth: nameWidth, isCurrent: isCurrent, isPicked: isPicked, showsCheckboxes: showsCheckboxes,
                  onPick: onPick, onActivate: onActivate, accessibilityName: accessibilityName, leading: EmptyView(), trailing: EmptyView())
    }
}

extension ListRow where Leading == EmptyView {
    init(_ name: String, lead: (any GlyphSource)? = nil, nameWidth: CGFloat? = nil, isCurrent: Bool = false, isPicked: Bool = false,
         showsCheckboxes: Bool = false, onPick: (() -> Void)? = nil, onActivate: (() -> Void)? = nil, accessibilityName: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(name: name, lead: lead, nameWidth: nameWidth, isCurrent: isCurrent, isPicked: isPicked, showsCheckboxes: showsCheckboxes,
                  onPick: onPick, onActivate: onActivate, accessibilityName: accessibilityName, leading: EmptyView(), trailing: trailing())
    }
}

extension ListRow {
    init(_ name: String, lead: (any GlyphSource)? = nil, nameWidth: CGFloat? = nil, isCurrent: Bool = false, isPicked: Bool = false,
         showsCheckboxes: Bool = false, onPick: (() -> Void)? = nil, onActivate: (() -> Void)? = nil, accessibilityName: String? = nil,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.init(name: name, lead: lead, nameWidth: nameWidth, isCurrent: isCurrent, isPicked: isPicked, showsCheckboxes: showsCheckboxes,
                  onPick: onPick, onActivate: onActivate, accessibilityName: accessibilityName, leading: leading(), trailing: trailing())
    }
}

/// The pick checkbox in a row's lead slot: 16 with radius 4, an `fg3` outline, or the accent with a white check when picked.
private struct RowCheckbox: View {
    let name: String
    let isPicked: Bool
    let onPick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.small, style: Metrics.Radius.cornerStyle)
        Button(action: onPick) {
            ZStack {
                shape.fill(isPicked ? Palette.accent : Palette.bgPanel)
                shape.strokeBorder(isPicked ? Palette.accent : Palette.fg3, lineWidth: Metrics.ListRow.checkboxBorder)
                if isPicked { SpaceVibeIcon(content: .check, size: .small, ink: Palette.onAccent) }
            }
            .frame(width: Metrics.ListRow.checkbox, height: Metrics.ListRow.checkbox)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityLabel("Pick \(name)")
        .accessibilityValue(isPicked ? "Picked" : "Not picked")
    }
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct ListRowFilledKey: ContainerValueKey {
    static let defaultValue = false
}

extension ContainerValues {
    /// Set by `ListRow`: its block is filled (hovered, current, picked or focused), so the dividers beside it hide.
    var listRowFilled: Bool {
        get { self[ListRowFilledKey.self] }
        set { self[ListRowFilledKey.self] = newValue }
    }
}

/// `ListRow`s, 44 apart with no gap between them. Under each row but the last sits a 1 pt `rowDivider`, from 34 after the row
/// block's leading edge to 8 before its trailing edge; it hides beside a filled row (V5-R23). The line after the last row of
/// a band, and before the next band, never shows.
struct ListRows<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group(subviews: content) { subviews in
            VStack(spacing: 0) {
                ForEach(Array(subviews.enumerated()), id: \.element.id) { offset, subview in
                    let isLast = offset == subviews.count - 1
                    let hidden = isLast || subview.containerValues.listRowFilled
                        || subviews[min(offset + 1, subviews.count - 1)].containerValues.listRowFilled
                    subview.overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Palette.rowDivider)
                            .frame(height: Metrics.Radius.edge)
                            .padding(.leading, Metrics.ListRow.dividerLeading)
                            .padding(.trailing, Metrics.ListRow.dividerTrailing)
                            .opacity(hidden ? 0 : 1)
                            .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hidden)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}
