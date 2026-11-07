import SwiftUI

/// A key cap: "⌘K", "Esc". 20 pt high, `label` type, filled with the control ground and no outline. Purely visual; the
/// control it labels carries the accessibility label.
struct Kbd: View {
    let keys: String
    @Environment(\.controlGround) private var ground

    init(_ keys: String) { self.keys = keys }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.kbdRadius, style: .continuous)
        Text(keys)
            .spaceVibeText(.label, tone: .secondary)
            .padding(.horizontal, Space.s6)
            .frame(minWidth: Metrics.kbdHeight, minHeight: Metrics.kbdHeight)
            .background(shape.fill(ground.fill))
            .accessibilityHidden(true)
    }
}
