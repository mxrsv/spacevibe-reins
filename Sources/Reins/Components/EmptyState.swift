import SwiftUI

/// Nothing to show on a whole screen or in a whole group: icon, one line, an optional second line and action.
struct EmptyState<Action: View>: View {
    let title: String
    var message: String?
    var icon: PageGlyph?
    let action: Action

    var body: some View {
        VStack(spacing: Space.s8) {
            if let icon {
                PageIcon(icon, size: .large)
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
    init(_ title: String, message: String? = nil, icon: PageGlyph? = nil) {
        self.title = title
        self.message = message
        self.icon = icon
        self.action = EmptyView()
    }
}

extension EmptyState {
    init(_ title: String, message: String? = nil, icon: PageGlyph? = nil, @ViewBuilder action: () -> Action) {
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
