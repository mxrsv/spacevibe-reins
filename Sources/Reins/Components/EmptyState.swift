import SwiftUI

/// Nothing to show on a whole screen or in a whole group: icon, one line, an optional second line and action.
struct EmptyState<Action: View>: View {
    let title: String
    var message: String?
    var icon: ReinsGlyph?
    let action: Action

    var body: some View {
        VStack(spacing: Space.s8) {
            if let icon {
                ReinsIcon(icon, size: .large)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, Space.s4)
            }
            Text(title).reinsText(.bodyStrong, tone: .primary)
            if let message {
                Text(message)
                    .reinsText(.caption, tone: .tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Metrics.emptyStateMessageWidth)
            }
            if Action.self != EmptyView.self { action.padding(.top, Space.s8) }
        }
        .padding(.horizontal, Space.s24)
        .padding(.vertical, Space.s32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyState where Action == EmptyView {
    init(_ title: String, message: String? = nil, icon: ReinsGlyph? = nil) {
        self.title = title
        self.message = message
        self.icon = icon
        self.action = EmptyView()
    }
}

extension EmptyState {
    init(_ title: String, message: String? = nil, icon: ReinsGlyph? = nil, @ViewBuilder action: () -> Action) {
        self.title = title
        self.message = message
        self.icon = icon
        self.action = action()
    }
}

/// A single muted row inside a `GroupedList`: "Nothing matches this filter."
struct EmptyRow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .reinsText(.caption, tone: .tertiary)
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .padding(.vertical, Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .groupedListPart(.plain)
    }
}

/// Nothing to show in a v5 card or list (V5-R54, V5-R62): a title (13/500, `fg2`), one sentence (`fg3`) and an optional
/// action 16 below, centred, with no icon. "Nothing matches" with `Clear filters` when filters hide every row; "No <items>"
/// when there are none. `placement` sets the padding: inside a card, or a whole list (the Skills list).
struct QuietEmptyState<Action: View>: View {
    enum Placement {
        case card, list

        var insets: EdgeInsets {
            switch self {
            case .card: Metrics.Tile.emptyInsets
            case .list: Metrics.EmptyState.listInsets
            }
        }
    }

    let title: String
    let message: String
    var placement: Placement = .card
    let action: Action

    var body: some View {
        VStack(spacing: 0) {
            Text(title).reinsText(.control, tone: .secondary).lineBox(.control).padding(.bottom, Metrics.EmptyState.titleSpacing)
            Text(message).reinsText(.prose, tone: .tertiary).fixedSize(horizontal: false, vertical: true).lineBox(.prose)
            if Action.self != EmptyView.self { action.padding(.top, Metrics.EmptyState.actionAbove) }
        }
        .multilineTextAlignment(.center)
        .padding(placement.insets)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension QuietEmptyState where Action == EmptyView {
    init(_ title: String, message: String, placement: Placement = .card) {
        self.init(title: title, message: message, placement: placement, action: EmptyView())
    }
}

extension QuietEmptyState {
    init(_ title: String, message: String, placement: Placement = .card, @ViewBuilder action: () -> Action) {
        self.init(title: title, message: message, placement: placement, action: action())
    }
}

/// A card's body while its data loads (V5-R54): three bars on the `track`, full, 72% and 48% wide, pulsing between half and
/// full opacity. The pulse is the app's one looping animation (V5-R42) and stops under reduced motion.
struct LoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Skeleton.spacing) {
            ForEach(Array(Metrics.Skeleton.widths.enumerated()), id: \.offset) { _, width in
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: Metrics.Radius.small, style: Metrics.Radius.cornerStyle)
                        .fill(Palette.track)
                        .frame(width: proxy.size.width * width)
                }
                .frame(height: Metrics.Skeleton.barHeight)
            }
        }
        .opacity(dimmed ? Metrics.Skeleton.pulseLow : 1)
        .padding(Metrics.Skeleton.insets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Metrics.Skeleton.pulse).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .onChange(of: reduceMotion) { _, reduce in
            if reduce { withAnimation(nil) { dimmed = false } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
