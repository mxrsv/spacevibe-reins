import SwiftUI

/// A key cap: "⌘K", "Esc". Purely visual; the control it labels carries the accessibility label.
struct Kbd: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(ReinsFont.kbd)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
