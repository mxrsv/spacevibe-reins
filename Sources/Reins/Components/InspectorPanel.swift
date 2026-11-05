import ReinsCore
import SwiftUI

/// The panel's width rules (spec, Interface: Panel; AG8): dragged between 420 and 720, Advanced opening at 720, and the
/// agent cards never narrower than 440, so the window's minimum width grows instead.
enum InspectorWidth {
    static let range: ClosedRange<CGFloat> = Metrics.inspectorMinWidth...Metrics.inspectorMaxWidth

    static func clamp(_ width: CGFloat) -> CGFloat { min(max(width, range.lowerBound), range.upperBound) }

    /// The width a drag of the leading edge gives: dragging left widens the panel.
    static func dragged(from start: CGFloat, by translation: CGFloat) -> CGFloat { clamp(start - translation) }

    /// The content width the page needs: the cards' minimum, plus the open panel and its divider.
    static func minimumContent(panel: CGFloat?) -> CGFloat {
        Metrics.agentCardsMinWidth + (panel.map { $0 + Metrics.dividerWidth } ?? 0)
    }
}

/// The right-hand inspector of the Agents page: it pushes the content aside rather than covering it, and is not a modal.
/// A 48 pt header (the small CLI mark, the panel's name, the agent's name, Close on Esc), a tools row, the scrolling body,
/// and, while a draft exists, a footer with "N unsaved changes", Discard and Review and save (⌘S). Leaving with a draft
/// turns the footer into the discard prompt instead of opening a second dialog. Its leading edge drags the width.
struct InspectorPanel<Tools: View, Content: View>: View {
    let cli: InventoryCLI
    let title: String
    let agent: String
    @Binding var width: CGFloat
    var draftCount = 0
    /// The footer asks "Discard N changes?" instead (Esc, Close, or a switch of panel or scope with a draft).
    var asksToDiscard = false
    let close: () -> Void
    let discard: () -> Void
    let keepEditing: () -> Void
    let review: () -> Void
    @ViewBuilder let tools: Tools
    @ViewBuilder let content: Content

    @State private var dragStart: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tools
                .padding(.horizontal, Space.s24)
                .padding(.bottom, Space.s16)
                .frame(maxWidth: .infinity, alignment: .leading)
            ReinsScrollView {
                VStack(alignment: .leading, spacing: Space.s16) { content }
                    .padding(.horizontal, Space.s24)
                    .padding(.bottom, Space.s24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if draftCount > 0 || asksToDiscard { footer }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.well)
        .overlay(alignment: .leading) { grip }
        .overlay(alignment: .leading) { Rectangle().fill(Palette.divider).frame(width: Metrics.dividerWidth).allowsHitTesting(false) }
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(agent)")
    }

    private var header: some View {
        HStack(spacing: Space.s12) {
            CLIMark(cli, size: .small)
            HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                Text(title).reinsText(.title, tone: .primary).lineLimit(1)
                Text(agent).reinsText(.caption, tone: .tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: close) { PageIcon(.close) }
                .buttonStyle(.reins(.icon))
                .help("Close (Esc)")
                .accessibilityLabel("Close panel")
        }
        .padding(.leading, Space.s24)
        .padding(.trailing, Space.s16)
        .frame(height: Metrics.topBarHeight)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: Space.s8) {
            if asksToDiscard {
                PageIcon(.warning, ink: Palette.warnInk)
                Text("Discard \(InspectorPanelWording.changes(draftCount))?").reinsText(.bodyStrong, tone: .warn)
                Spacer(minLength: 0)
                Button("Keep editing", action: keepEditing).buttonStyle(.reins(.ghost))
                Button("Discard", action: discard).buttonStyle(.reins(.danger))
            } else {
                Text(InspectorPanelWording.unsaved(draftCount)).reinsText(.body, tone: .secondary)
                Spacer(minLength: 0)
                Button("Discard", action: discard).buttonStyle(.reins(.ghost))
                Button(action: review) { ButtonLabel("Review and save") }
                    .buttonStyle(.reins(.primary))
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, Space.s24)
        .padding(.vertical, Space.s12)
        .frame(maxWidth: .infinity)
        .background(asksToDiscard ? Palette.warnTint : Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.divider).frame(height: Metrics.dividerWidth) }
        .controlGround(.card)
    }

    /// An 8 pt strip over the leading edge; a drag sets the width within 420 to 720.
    private var grip: some View {
        Color.clear
            .frame(width: Metrics.inspectorGripWidth)
            .contentShape(Rectangle())
            .offset(x: -Metrics.inspectorGripWidth / 2)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? width
                        dragStart = start
                        width = InspectorWidth.dragged(from: start, by: drag.translation.width)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityHidden(true)
    }
}

/// The panel footer's words. Pure, so the tests pin them.
enum InspectorPanelWording {
    static func changes(_ count: Int) -> String { count == 1 ? "1 change" : "\(count) changes" }
    static func unsaved(_ count: Int) -> String { count == 1 ? "1 unsaved change" : "\(count) unsaved changes" }
}
