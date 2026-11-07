import SwiftUI

/// The Skills canvas (V5-R18, V5-R32): the list column at 46% of the width with the order line above it and a `hair` line at
/// its right edge, the permanent pane in the rest, and the bottom bar floating 48 above the panel's bottom while one is
/// given. The bar's presence lifts the toast (104 instead of 48): the layout tells the toast center. Layout only: the list's
/// rows, the pane and the bar draw themselves.
///
///     ListPaneLayout(orderLine: "Ordered by sessions", scrollTarget: current, barShown: !picked.isEmpty) {
///         ListRows { ... }
///     } pane: { DetailPane { ... } } bar: { BulkBar(...) }
struct ListPaneLayout<List: View, Pane: View, Bar: View>: View {
    let orderLine: String
    /// Scrolled into view when it changes (the id of a row inside `list`).
    var scrollTarget: String?
    var barShown: Bool
    @ViewBuilder var list: List
    @ViewBuilder var pane: Pane
    @ViewBuilder var bar: Bar

    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    OrderLine(text: orderLine)
                    ScrollViewReader { reader in
                        SpaceVibeScrollView { list.padding(Metrics.SkillsList.listInsets) }
                            .onChange(of: scrollTarget) { _, target in
                                guard let target else { return }
                                withAnimation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick)) { reader.scrollTo(target) }
                            }
                    }
                }
                .frame(width: proxy.size.width * Metrics.SkillsList.widthFraction)
                .overlay(alignment: .trailing) { Rectangle().fill(Palette.hair).frame(width: Metrics.Radius.edge).accessibilityHidden(true) }
                pane.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .bottom) {
                if barShown {
                    bar
                        .padding(.bottom, Metrics.SkillsSplit.barBottom)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Metrics.Motion.quick), value: barShown)
        .onChange(of: barShown, initial: true) { _, shown in toasts.isOverBottomBar = shown }
        .onDisappear { toasts.isOverBottomBar = false }
    }
}

/// The line above the list (V5-R30): 32 high, "Ordered by sessions · Grouped by status" in 11 `fg3`.
struct OrderLine: View {
    let text: String

    var body: some View {
        Text(text)
            .spaceVibeText(.small, tone: .tertiary)
            .lineLimit(1)
            .padding(Metrics.SkillsList.orderLineInsets)
            .frame(height: Metrics.SkillsList.orderLineHeight, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
