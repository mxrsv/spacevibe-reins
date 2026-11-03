import SwiftUI

/// A pill that filters a list. Several chips side by side act as one single-choice filter; the caller owns the
/// state. `count` is how many rows the filter would show.
struct FilterChip: View {
    let title: String
    var count: Int?
    let isOn: Bool
    let action: () -> Void

    init(_ title: String, count: Int? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let count { Text("\(count)").font(ReinsFont.small).foregroundStyle(Palette.textTertiary) }
            }
            .font(ReinsFont.body)
            .foregroundStyle(isOn ? Palette.text : Palette.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: Metrics.chipHeight)
            .background(Capsule().fill(isOn ? Palette.selection : .clear))
            .overlay(Capsule().strokeBorder(isOn ? .clear : Palette.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .reinsFocusable(cornerRadius: Metrics.chipHeight / 2)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityHint("Filter")
    }
}
