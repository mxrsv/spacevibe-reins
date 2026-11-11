import SwiftUI

/// One entry of the Limits page's window list, a block of its own on the well (layout H): the CLI's mark, the window's name
/// with its tags, a `caption` line ("Codex · resets in 3 h 12 min"), a small ruler under the text and the share on the
/// right. `surface` at rest, `surfaceRaised` on hover, `selection` over `surface` when chosen. A CLI with no window has no
/// ruler (`meter: .none`); a window past its reset draws the dashed outline (`.unknown`).
struct LimitWindowTile<Tags: View>: View {
    enum Meter {
        case share(Double, fill: Color)
        case unknown
        case none
    }

    let cli: CoreLimitsCLI
    let title: String
    let subtitle: String
    let meter: Meter
    /// "39%", or "—" / "unknown" when nothing is known.
    let value: String
    var valueTone: TextTone = .primary
    var selected = false
    let onActivate: () -> Void
    let tags: Tags

    @State private var hovering = false
    @Environment(\.specimenInteraction) private var specimen
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
        HStack(spacing: Metrics.rowSpacing) {
            CLIMark(cli, size: .medium)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s8) {
                    Text(title).spaceVibeText(.bodyStrong, tone: .primary).lineLimit(1)
                    tags
                }
                .frame(height: SpaceVibeType.bodyStrong.lineBox)
                Text(subtitle).spaceVibeText(.caption, tone: .secondary).lineLimit(1)
                ruler.padding(.top, Space.s8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One width for "4%", "100%" and "unknown", so the rulers of the list end on one line.
            Text(value)
                .spaceVibeText(isKnown ? .title : .caption, tone: isKnown ? valueTone : .tertiary)
                .lineLimit(1)
                .frame(minWidth: Metrics.usageNumberWidth, alignment: .trailing)
        }
        .padding(Space.s12)
        .background {
            // `selection` is translucent, so it lies over `surface`; on the bare well it would read darker than the others.
            ZStack {
                shape.fill(hovering && !selected ? Palette.surfaceRaised : Palette.surface)
                if selected { shape.fill(Palette.selection) }
            }
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .modifier(RowActivation(onActivate: onActivate, focused: $focused))
        .focusFill(focused || specimen.contains(.focus), cornerRadius: Metrics.rowRadius)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var isKnown: Bool {
        if case .share = meter { return true }
        return false
    }

    @ViewBuilder
    private var ruler: some View {
        switch meter {
        case .share(let share, let fill):
            Ruler(share: share, fill: fill, emptyFill: selected ? Palette.trackOnSelection : Palette.track)
        case .unknown:
            Ruler(share: nil, fill: cli.fill)
        case .none:
            EmptyView()
        }
    }
}

extension LimitWindowTile where Tags == EmptyView {
    init(cli: CoreLimitsCLI, title: String, subtitle: String, meter: Meter, value: String, valueTone: TextTone = .primary,
         selected: Bool = false, onActivate: @escaping () -> Void) {
        self.init(cli: cli, title: title, subtitle: subtitle, meter: meter, value: value, valueTone: valueTone,
                  selected: selected, onActivate: onActivate, tags: EmptyView())
    }
}

extension LimitWindowTile {
    init(cli: CoreLimitsCLI, title: String, subtitle: String, meter: Meter, value: String, valueTone: TextTone = .primary,
         selected: Bool = false, onActivate: @escaping () -> Void, @ViewBuilder tags: () -> Tags) {
        self.init(cli: cli, title: title, subtitle: subtitle, meter: meter, value: value, valueTone: valueTone,
                  selected: selected, onActivate: onActivate, tags: tags())
    }
}
