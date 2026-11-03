import SwiftUI

/// A pill that filters a list, 28 pt high like every control, with no outline: the control ground's fill, or the `selection`
/// tint while on. Several chips side by side act as one single-choice filter; the caller owns the state. `count` is how many
/// rows the filter would show.
///
/// The dismissible form is an applied scope ("spacevibe-bench ×"): always on, and only the × acts. The × is its own
/// button with a spoken label, so a keyboard user reaches it directly.
struct FilterChip: View {
    let title: String
    var count: Int?
    let isOn: Bool
    let action: () -> Void
    var onDismiss: (() -> Void)?
    @Environment(\.controlGround) private var ground

    init(_ title: String, count: Int? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isOn = isOn
        self.action = action
    }

    /// An applied scope that the × clears.
    init(dismissible title: String, onDismiss: @escaping () -> Void) {
        self.title = title
        isOn = true
        action = {}
        self.onDismiss = onDismiss
    }

    var body: some View {
        if let onDismiss {
            pill(trailing: Space.s8) {
                Text(title)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").imageScale(.small).foregroundStyle(TextTone.secondary.color)
                }
                .buttonStyle(.plain)
                .reinsFocusable(cornerRadius: Metrics.segmentRadius)
                .help("Clear \(title)")
                .accessibilityLabel("Clear \(title)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Button(action: action) {
                pill(trailing: Space.s12) {
                    Text(title)
                    if let count { Count(count) }
                }
            }
            .buttonStyle(.plain)
            .reinsFocusable(cornerRadius: Metrics.chipHeight / 2)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
            .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
            .accessibilityHint("Filter")
        }
    }

    private func pill<Content: View>(trailing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Space.s6) { content() }
            .reinsText(.body, tone: isOn ? .primary : .secondary)
            .padding(.leading, Space.s12)
            .padding(.trailing, trailing)
            .frame(height: Metrics.chipHeight)
            .background(Capsule().fill(isOn ? Palette.selection : ground.fill))
            .contentShape(Capsule())
    }
}
