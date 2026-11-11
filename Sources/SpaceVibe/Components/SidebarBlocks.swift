import SwiftUI

/// The blocks of the v5 sidebar (V5-R50) and the content panel (V5-R51), beside the old 48 pt `SidebarItem` that the
/// cut-over (X1) deletes. The shell composes these and paints nothing itself (UP1).

extension View {
    /// The sidebar column: 220 wide on `bgSide`, padding 16 at the sides and the bottom. The window buttons' row (48) is the
    /// shell's first child, because the native traffic lights sit there.
    func appSidebarSurface() -> some View {
        padding(.horizontal, Rhythm.side)
            .padding(.bottom, Rhythm.side)
            .frame(width: Metrics.AppSidebar.width)
            .frame(maxHeight: .infinity)
            .background(Palette.bgSide)
    }
}

/// The product row (40, padding 0 12): the app's initial in a 20 pt accent tile and the name in 13/600. Name and initial
/// come from one constant (`SpaceVibeMark.productName`).
struct SidebarProductRow: View {
    let name: String

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        HStack(spacing: Metrics.AppSidebar.itemGap) {
            Text(String(name.prefix(1)))
                .spaceVibeText(SpaceVibeType.smallLabel.weight(.semibold))
                .foregroundStyle(Palette.onAccent)
                .frame(width: Metrics.AppSidebar.markSize, height: Metrics.AppSidebar.markSize)
                .background(tile.fill(Palette.accent))
                .overlay { TopEdgeHighlight(radius: Metrics.Radius.control).fill(Palette.hiOnSolid).allowsHitTesting(false) }
                .accessibilityHidden(true)
            Text(name).spaceVibeText(.controlStrong, tone: .primary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.AppSidebar.itemPadding)
        .frame(height: Metrics.AppSidebar.itemHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The search row (40, a `hair` edge on `bgApp`, radius 6): the search glyph, "Search" in `fg3` and the `⌘K` key cap. It
/// opens the command palette; the page items are 4 apart, so the shell puts 8 above it and 20 below.
struct SidebarSearchRow: View {
    var title = "Search"
    let keyCap: String
    /// The shortcut as VoiceOver says it ("Command K").
    let spokenKey: String
    let action: () -> Void

    @Environment(\.specimenInteraction) private var specimen
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let lifted = hovering || specimen.contains(.hover)
        let isFocused = focused || specimen.contains(.focus)
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        Button(action: action) {
            HStack(spacing: Metrics.AppSidebar.itemGap) {
                SpaceVibeIcon(content: .search, ink: lifted ? Palette.fg : Palette.fg2)
                Text(title).spaceVibeText(.prose, tone: .tertiary).lineLimit(1)
                Spacer(minLength: 0)
                KeyCap(keyCap)
            }
            .padding(.horizontal, Metrics.AppSidebar.itemPadding)
            .frame(height: Metrics.AppSidebar.itemHeight)
            .background(shape.fill(isFocused ? Palette.sel : (lifted ? Palette.hover : Palette.bgApp)))
            .overlay { shape.strokeBorder(Palette.hair, lineWidth: Metrics.Radius.edge).allowsHitTesting(false) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .focused($focused)
        .focusEffectDisabled()
        .focusFill(isFocused, cornerRadius: Metrics.Radius.control)
        .onHover { hovering = $0 }
        .accessibilityLabel("Search and commands")
        .accessibilityHint(spokenKey)
    }
}

/// A page item (40, padding 0 12, radius 6): glyph (16) and label 8 apart, the total count at the right in 12 pt `fg3`.
/// The glyph is `fg` at 80% and 100% on hover and when current; the label turns `fg2` to `fg`, and the current item takes the
/// `sel` fill and weight 500. Hover and focus are one fill each, never stacked on the current item's.
struct SidebarPageItem: View {
    let title: String
    let glyph: any GlyphSource
    var count: Int?
    /// What VoiceOver reads for the count ("22 items"); the number when nil.
    var spokenCount: String?
    let isCurrent: Bool
    let action: () -> Void

    @Environment(\.specimenInteraction) private var specimen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let lifted = hovering || specimen.contains(.hover)
        let isFocused = focused || specimen.contains(.focus)
        let strong = isCurrent || lifted
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        Button(action: action) {
            HStack(spacing: Metrics.AppSidebar.itemGap) {
                SpaceVibeIcon(source: glyph, ink: Palette.fg)
                    .opacity(strong ? 1 : Metrics.AppSidebar.restGlyphOpacity)
                Text(title)
                    .spaceVibeText(isCurrent ? .control : .prose)
                    .foregroundStyle(strong ? Palette.fg : Palette.fg2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let count { Text("\(count)").spaceVibeText(.meta, tone: .tertiary) }
            }
            .padding(.horizontal, Metrics.AppSidebar.itemPadding)
            .frame(height: Metrics.AppSidebar.itemHeight)
            .background(shape.fill(isCurrent || isFocused ? Palette.sel : (lifted ? Palette.hover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .focused($focused)
        .focusEffectDisabled()
        .focusFill(isFocused, cornerRadius: Metrics.Radius.control)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: lifted)
        .accessibilityLabel(count.map { "\(title), \(spokenCount ?? String($0))" } ?? title)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}

/// What a CLI's status row says (V5-R50): the three states of the mock. The dot is `ok` while the app reads the CLI and
/// `mute` otherwise. The shell derives the state from what it can know (`CLIStatusDerivation`); a state it cannot derive is
/// not drawn.
enum SidebarCLIState: Equatable, Sendable {
    case reading, notInstalled, noLog

    var label: String {
        switch self {
        case .reading: "reading"
        case .notInstalled: "not installed"
        case .noLog: "no log"
        }
    }

    var isOK: Bool { self == .reading }
}

/// A CLI status row (32, padding 0 12): its logo (14), its name in 12 pt `fg2`, and at the right a 6 pt dot and the state in
/// 11 pt `fg3`. With no state only the name shows. Not interactive.
struct SidebarCLIStatusRow: View {
    let name: String
    let cli: CoreLimitsCLI
    var state: SidebarCLIState?

    var body: some View {
        // No gap around the spacer: "Gemini CLI" and `not installed` share the 164 pt inside the row's padding and need all of it.
        HStack(spacing: 0) {
            CLIMark(cli, size: .glyph)
            Text(name).spaceVibeText(.meta, tone: .secondary).lineLimit(1).padding(.leading, Metrics.AppSidebar.itemGap)
            Spacer(minLength: 0)
            if let state {
                HStack(spacing: Metrics.AppSidebar.statusDotGap) {
                    Circle().fill(state.isOK ? Palette.ok : Palette.mute)
                        .frame(width: Metrics.AppSidebar.statusDot, height: Metrics.AppSidebar.statusDot)
                    Text(state.label).spaceVibeText(.small, tone: .tertiary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Metrics.AppSidebar.itemPadding)
        .frame(height: Metrics.AppSidebar.statusRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.map { "\(name), \($0.label)" } ?? name)
    }
}

/// The CLI status rows: 4 apart under a `hair` line, 12 below it, 8 above the footer.
struct SidebarCLIStatusGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Metrics.AppSidebar.statusRowSpacing) { content }
            .padding(.top, Metrics.AppSidebar.statusAbove)
            .overlay(alignment: .top) { Rectangle().fill(Palette.hair).frame(height: Metrics.Radius.edge).accessibilityHidden(true) }
            .padding(.bottom, Metrics.AppSidebar.statusBelow)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Command line tools")
    }
}

/// The footer's wide button (36, padding 0 12, radius 6): a glyph and a label in 13 pt `fg2`, `fg` on hover and focus, with
/// the `hover` fill and, focused, the `sel` fill.
struct SidebarFooterButton: View {
    let title: String
    let glyph: any GlyphSource
    var keyHint: String?
    let action: () -> Void

    var body: some View {
        SidebarFooterControl(label: title, hint: keyHint, action: action) {
            HStack(spacing: Metrics.AppSidebar.itemGap) {
                SpaceVibeIcon(source: glyph)
                Text(title).spaceVibeText(.prose).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.AppSidebar.itemPadding)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The footer's square button (36 x 36): the appearance toggle.
struct SidebarIconButton: View {
    let glyph: any GlyphSource
    let label: String
    let action: () -> Void

    var body: some View {
        SidebarFooterControl(label: label, hint: nil, action: action) {
            SpaceVibeIcon(source: glyph).frame(width: Metrics.AppSidebar.footerButtonHeight)
        }
    }
}

private struct SidebarFooterControl<Content: View>: View {
    let label: String
    let hint: String?
    let action: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.specimenInteraction) private var specimen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let lifted = hovering || specimen.contains(.hover)
        let isFocused = focused || specimen.contains(.focus)
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
        Button(action: action) {
            content
                .foregroundStyle(lifted || isFocused ? Palette.fg : Palette.fg2)
                .frame(height: Metrics.AppSidebar.footerButtonHeight)
                .background(shape.fill(isFocused ? Palette.sel : (lifted ? Palette.hover : .clear)))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .focused($focused)
        .focusEffectDisabled()
        .focusFill(isFocused, cornerRadius: Metrics.Radius.control)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: lifted)
        .accessibilityLabel(label)
        .help(hint.map { "\(label) (\($0))" } ?? label)
    }
}

/// The content panel (V5-R51): inset 12 from the window on top, right and bottom, `bgPanel` with a `hair` edge and the
/// top-edge highlight, radius 8. The page fills it, tab head included, and the status bar closes it: the page's working keys
/// at the left, the data source at the right.
struct ContentPanel<Content: View>: View {
    var hints: [KeyHint] = []
    var source: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBar(hints: hints, source: source)
        }
        // Inside the 1 pt edge, as the kit's border does (CSS border-box).
        .padding(Metrics.Radius.edge)
        .blockSurface(Palette.bgPanel, edge: Palette.hair)
        .padding(.top, Metrics.ContentPanel.inset)
        .padding(.trailing, Metrics.ContentPanel.inset)
        .padding(.bottom, Metrics.ContentPanel.inset)
    }
}
