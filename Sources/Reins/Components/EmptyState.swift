import SwiftUI

/// Nothing to show on a whole screen or in a whole group: icon, one line, an optional second line and action.
struct EmptyState<Action: View>: View {
    let title: String
    var message: String?
    var systemImage: String?
    let action: Action

    var body: some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            Text(title).font(ReinsFont.bodyStrong).foregroundStyle(Palette.text)
            if let message {
                Text(message)
                    .font(ReinsFont.small)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            action
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyState where Action == EmptyView {
    init(_ title: String, message: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = EmptyView()
    }
}

extension EmptyState {
    init(_ title: String, message: String? = nil, systemImage: String? = nil, @ViewBuilder action: () -> Action) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action()
    }
}

/// A single muted row inside a `GroupedList`: "Nothing matches this filter."
struct EmptyRow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(ReinsFont.small)
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
