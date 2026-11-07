import SwiftUI

/// One line of a `GroupedList`, 48 pt high: a 20 pt lead slot, the growing text block (`RowText`), always-visible cells
/// (usage cells, counts, tags) and trailing actions that appear on hover, on keyboard focus and while selected. `tall`
/// is for three lines or more: 12 pt above and below instead of 6.
///
/// The row is a block inset 8 pt from the card's edges, with no border. Hover (on a row with `onActivate`) and selection
/// fill that block with radius 8, and the card hides the dividers on both sides of it.
///
///     Row { RowText("ponytail", subtitle: "Pick the laziest solution") }
///         .lead { ReinsIcon(.skill, size: .row) }
///         .cells { UsageCell(cli: .claude, model: .counted(runs: 142), max: 142) }
///         .actions { RowActionButton(title: "Remove", icon: .trash, iconOnly: true) { ... } }
///
/// With `onActivate` the whole row is focusable and acts on Return and Space; inner buttons keep their own action.
/// Actions must be `RowActionButton`s (or any `ReinsButtonStyle` button) so they hide and reveal with the row.
struct Row<Lead: View, Main: View, Cells: View, Actions: View>: View {
    var selected = false
    var tall = false
    /// Keeps the actions visible without hover (the gallery uses it; selected rows reveal them anyway).
    var revealActions = false
    var onActivate: (() -> Void)?
    let leadView: Lead
    let main: Main
    let cellsView: Cells
    let actionsView: Actions

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let revealed = hovering || selected || revealActions || focused
        let block = RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
        HStack(spacing: Metrics.rowSpacing) {
            // The slot keeps its width when a row has no lead, so titles line up down the list.
            Color.clear
                .frame(width: Metrics.rowLeadWidth, height: 1)
                .overlay { leadView.foregroundStyle(Palette.textTertiary).fixedSize() }
            main.frame(maxWidth: .infinity, alignment: .leading)
            cellsView
            actionsView.environment(\.actionsConcealed, !revealed)
        }
        .padding(.horizontal, Metrics.rowInnerPadding)
        .padding(.vertical, tall ? Metrics.tallRowVerticalPadding : Metrics.rowVerticalPadding)
        .frame(minHeight: Metrics.rowMinHeight)
        .background(block.fill(fill))
        .contentShape(block)
        .onHover { hovering = $0 }
        .modifier(RowActivation(onActivate: onActivate, focused: $focused))
        // A selected row already wears `selection`; a second fill would put tertiary text under 4.5:1 (ContrastTests).
        .focusFill(focused && !selected, cornerRadius: Metrics.rowRadius)
        .padding(.horizontal, Metrics.rowInset)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .containerValue(\.groupedListFilled, isFilled)
    }

    private var isFilled: Bool { selected || (hovering && onActivate != nil) }

    private var fill: Color {
        if selected { return Palette.selection }
        if hovering && onActivate != nil { return Palette.hover }
        return .clear
    }
}

/// Focusable, Return and Space act, a click acts, and VoiceOver's default action acts; nothing without `onActivate`.
/// `LimitWindowTile` uses it too, so a tile and a row answer the same keys.
struct RowActivation: ViewModifier {
    let onActivate: (() -> Void)?
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if let onActivate {
            content
                .focusable()
                .focused(focused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.return, .space]) { _ in
                    onActivate()
                    return .handled
                }
                .onTapGesture(perform: onActivate)
                .accessibilityAction(.default, onActivate)
        } else {
            content
        }
    }
}

extension Row where Lead == EmptyView, Cells == EmptyView, Actions == EmptyView {
    init(selected: Bool = false, tall: Bool = false, revealActions: Bool = false, onActivate: (() -> Void)? = nil, @ViewBuilder main: () -> Main) {
        self.selected = selected
        self.tall = tall
        self.revealActions = revealActions
        self.onActivate = onActivate
        self.leadView = EmptyView()
        self.main = main()
        self.cellsView = EmptyView()
        self.actionsView = EmptyView()
    }
}

extension Row {
    func lead<L: View>(@ViewBuilder _ build: () -> L) -> Row<L, Main, Cells, Actions> {
        Row<L, Main, Cells, Actions>(selected: selected, tall: tall, revealActions: revealActions, onActivate: onActivate,
                                     leadView: build(), main: main, cellsView: cellsView, actionsView: actionsView)
    }

    func cells<C: View>(@ViewBuilder _ build: () -> C) -> Row<Lead, Main, C, Actions> {
        Row<Lead, Main, C, Actions>(selected: selected, tall: tall, revealActions: revealActions, onActivate: onActivate,
                                    leadView: leadView, main: main, cellsView: build(), actionsView: actionsView)
    }

    func actions<A: View>(@ViewBuilder _ build: () -> A) -> Row<Lead, Main, Cells, A> {
        Row<Lead, Main, Cells, A>(selected: selected, tall: tall, revealActions: revealActions, onActivate: onActivate,
                                  leadView: leadView, main: main, cellsView: cellsView, actionsView: build())
    }
}
