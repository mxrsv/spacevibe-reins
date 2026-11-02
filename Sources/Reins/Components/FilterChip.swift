import SwiftUI

/// A pill that filters a list. Several chips side by side act as one single-choice filter; the caller owns the
/// state. `count` is how many rows the filter would show.
///
/// The dismiss variant (`FilterChip(dismissing:)`) stands for a scope that is on, such as a picked day: it always looks
/// selected, ends in an ×, and pressing it clears that scope. VoiceOver reads it as "Clear <title>".
struct FilterChip: View {
    let title: String
    var count: Int?
    let isOn: Bool
    private var dismisses = false
    let action: () -> Void

    @FocusState private var focused: Bool

    init(_ title: String, count: Int? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isOn = isOn
        self.action = action
    }

    init(dismissing title: String, action: @escaping () -> Void) {
        self.title = title
        self.count = nil
        self.isOn = true
        self.dismisses = true
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                if let count { Text("\(count)").font(ReinsFont.small).foregroundStyle(Palette.textTertiary) }
                if dismisses {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .font(ReinsFont.body)
            .foregroundStyle(isOn ? Palette.text : Palette.textSecondary)
            .padding(.leading, 10)
            .padding(.trailing, dismisses ? 8 : 10)
            .frame(height: Metrics.chipHeight)
            .background(Capsule().fill(isOn ? Palette.selection : .clear))
            .overlay(Capsule().strokeBorder(isOn ? .clear : Palette.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .focusRing(focused, cornerRadius: Metrics.chipHeight / 2)
        .accessibilityAddTraits(isOn && !dismisses ? [.isSelected] : [])
        .accessibilityLabel(dismisses ? "Clear \(title)" : count.map { "\(title), \($0)" } ?? title)
        .accessibilityHint(dismisses ? "Removes this scope" : "Filter")
    }
}
