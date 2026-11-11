import Observation
import SwiftUI

/// A disclosure group inside a card or the Skills list (V5-R55): a header 44 high on `bgBand` (treatment 1) with the
/// chevron, an optional logo or glyph, the label (13/600), a count, an optional state glyph and right-aligned extras; the
/// body shows while open. Put bands in a `BandStack`, which spaces them. The open state is the caller's: a page reads it from
/// `OpenStateStore`.
///
///     BandStack {
///         Band("Claude Code", count: 3, state: low, isOpen: store.binding(page: "limits", id: "claude", byDefault: true)) {
///             ListRows { ... }
///         } lead: { CLIMark(.claude, size: .control) }
///     }
struct Band<Lead: View, Extras: View, Content: View>: View {
    let label: String
    var count: Int?
    var state: StateMark?
    @Binding var isOpen: Bool
    let lead: Lead
    let extras: Extras
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader(label: label, count: count, state: state, isOpen: $isOpen, lead: lead, extras: extras)
            if isOpen { content }
        }
        .containerValue(\.bandIsOpen, isOpen)
    }
}

extension Band where Lead == EmptyView, Extras == EmptyView {
    init(_ label: String, count: Int? = nil, state: StateMark? = nil, isOpen: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(label: label, count: count, state: state, isOpen: isOpen, lead: EmptyView(), extras: EmptyView(), content: content())
    }
}

extension Band where Extras == EmptyView {
    init(_ label: String, count: Int? = nil, state: StateMark? = nil, isOpen: Binding<Bool>, @ViewBuilder content: () -> Content,
         @ViewBuilder lead: () -> Lead) {
        self.init(label: label, count: count, state: state, isOpen: isOpen, lead: lead(), extras: EmptyView(), content: content())
    }
}

extension Band {
    init(_ label: String, count: Int? = nil, state: StateMark? = nil, isOpen: Binding<Bool>, @ViewBuilder content: () -> Content,
         @ViewBuilder lead: () -> Lead, @ViewBuilder extras: () -> Extras) {
        self.init(label: label, count: count, state: state, isOpen: isOpen, lead: lead(), extras: extras(), content: content())
    }
}

/// The band's header: a button that opens and closes the band. Rest `bgBand`, hovered `bgBandHover`, focused `bgBandFocus`
/// (D57); hovered and focused together take the focus fill alone.
private struct BandHeader<Lead: View, Extras: View>: View {
    let label: String
    let count: Int?
    let state: StateMark?
    @Binding var isOpen: Bool
    let lead: Lead
    let extras: Extras

    @Environment(\.specimenInteraction) private var specimen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle)
        let isFocused = focused || specimen.contains(.focus)
        let hovered = hovering || specimen.contains(.hover)
        HStack(spacing: Metrics.Band.spacing) {
            SpaceVibeIcon(content: .caretDown, size: .small, ink: Palette.fg3)
                .rotationEffect(.degrees(isOpen ? 0 : -90))
                .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: isOpen)
            lead
            Text(label).spaceVibeText(.controlStrong, tone: .primary).lineLimit(1)
            if let count { Text("\(count)").spaceVibeText(.meta, tone: .tertiary).lineLimit(1).fixedSize() }
            if let state {
                StateMarkIcon(mark: state).padding(.leading, Metrics.Band.stateSpacing - Metrics.Band.spacing)
            }
            Spacer(minLength: 0)
            extras
        }
        .padding(.leading, Metrics.Band.leading)
        .padding(.trailing, Metrics.Band.trailing)
        .frame(height: Metrics.Band.headerHeight)
        .background(shape.fill(isFocused ? Palette.bgBandFocus : hovered ? Palette.bgBandHover : Palette.bgBand))
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: hovered)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .modifier(RowActivation(onActivate: { isOpen.toggle() }, focused: $focused))
        .focusFill(isFocused, cornerRadius: Metrics.Radius.block)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([label, count.map { "\($0)" }, state?.label].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
    }
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct BandIsOpenKey: ContainerValueKey {
    static let defaultValue = false
}

extension ContainerValues {
    /// Set by `Band`, so `BandStack` can space and group the bands by their state.
    var bandIsOpen: Bool {
        get { self[BandIsOpenKey.self] }
        set { self[BandIsOpenKey.self] = newValue }
    }
}

/// How `BandStack` lays out a run of closed bands that follow each other.
enum ClosedBandLayout {
    /// One under the other, 10 apart.
    case stack
    /// Their headers in a two-column grid, 8 apart (Hooks).
    case grid
}

/// Bands in a card or list (V5-R55): none above the first, 32 above every other, 10 between closed bands that follow each
/// other, or those in a two-column grid on Hooks.
struct BandStack<Content: View>: View {
    var closedRuns: ClosedBandLayout = .stack
    @ViewBuilder var content: Content

    var body: some View {
        Group(subviews: content) { subviews in
            let segments = Self.segments(Array(subviews), grid: closedRuns == .grid)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { offset, segment in
                    let previous = offset == 0 ? nil : segments[offset - 1]
                    Group {
                        if segment.isGrid { grid(segment.bands) } else { segment.bands[0] }
                    }
                    .padding(.top, spacing(after: previous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func spacing(after previous: Segment?) -> CGFloat {
        guard let previous else { return 0 }
        return !previous.isGrid && !previous.bands[0].containerValues.bandIsOpen ? Metrics.Band.collapsedSpacing : Rhythm.group
    }

    private func grid(_ bands: [Subview]) -> some View {
        let columns = Metrics.Band.gridColumns
        let rows = stride(from: 0, to: bands.count, by: columns).map { Array(bands[$0 ..< min($0 + columns, bands.count)]) }
        return VStack(spacing: Metrics.Band.gridSpacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: Metrics.Band.gridSpacing) {
                    ForEach(row) { band in band.frame(maxWidth: .infinity) }
                    ForEach(0 ..< columns - row.count, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                }
            }
        }
    }

    /// One band, or (in a grid) a run of closed bands.
    private struct Segment: Identifiable {
        let bands: [Subview]
        let isGrid: Bool
        var id: Subview.ID { bands[0].id }
    }

    private static func segments(_ bands: [Subview], grid: Bool) -> [Segment] {
        var result: [Segment] = []
        var run: [Subview] = []
        for band in bands {
            if grid && !band.containerValues.bandIsOpen {
                run.append(band)
                continue
            }
            if !run.isEmpty { result.append(Segment(bands: run, isGrid: true)); run = [] }
            result.append(Segment(bands: [band], isGrid: false))
        }
        if !run.isEmpty { result.append(Segment(bands: run, isGrid: true)) }
        return result
    }
}

/// Which bands (and cards) are open, per page and band, for as long as the app runs (V5-R55); never saved.
///
/// - A choice the user made wins.
/// - Otherwise the band takes its default (`defaultOpen`), but a band once shown open stays open when its default turns
///   closed, so a write (or a refresh) never folds the band of the row it changed. A band closed by default opens when its
///   default turns open (a new problem).
@Observable
final class OpenStateStore {
    static let shared = OpenStateStore()

    private struct Key: Hashable {
        let page: String
        let id: String
    }

    private var chosen: [Key: Bool] = [:]
    /// Read while a view draws, so it is not observed: it only ever keeps a band open that is already drawn open.
    @ObservationIgnored private var shownOpen: Set<Key> = []

    func isOpen(page: String, id: String, byDefault: Bool) -> Bool {
        let key = Key(page: page, id: id)
        if let choice = chosen[key] { return choice }
        if byDefault { shownOpen.insert(key) }
        return byDefault || shownOpen.contains(key)
    }

    func setOpen(_ open: Bool, page: String, id: String) {
        chosen[Key(page: page, id: id)] = open
    }

    func binding(page: String, id: String, byDefault: Bool) -> Binding<Bool> {
        Binding(get: { self.isOpen(page: page, id: id, byDefault: byDefault) }, set: { self.setOpen($0, page: page, id: id) })
    }

    /// V5-R55's default: a band that holds a problem opens; when nothing on the page needs the user, the first band opens;
    /// every other band starts closed.
    static func defaultOpen(holdsProblem: Bool, isFirst: Bool, pageNeedsUser: Bool) -> Bool {
        holdsProblem || (!pageNeedsUser && isFirst)
    }
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct OpenStateStoreKey: EnvironmentKey {
    static let defaultValue = OpenStateStore.shared
}

extension EnvironmentValues {
    /// The app's one `OpenStateStore`; a test or a gallery passes its own.
    var openStateStore: OpenStateStore {
        get { self[OpenStateStoreKey.self] }
        set { self[OpenStateStoreKey.self] = newValue }
    }
}
