import SwiftUI

/// A key cap: "⌘K", "Esc". 20 pt high, `label` type. Purely visual; the control it labels carries the accessibility label.
struct Kbd: View {
    let keys: String

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.kbdRadius, style: .continuous)
        Text(keys)
            .reinsText(.label, tone: .secondary)
            .padding(.horizontal, Space.s6)
            .frame(minWidth: Metrics.tagHeight, minHeight: Metrics.tagHeight)
            .background(shape.fill(Palette.surface))
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
