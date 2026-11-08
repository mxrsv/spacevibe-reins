import AppKit
import SwiftUI

/// The pointer over a control (V5-R8, V5-R25). A block that takes a click applies `pointerCursor()` itself: a button style
/// in its `makeBody`, a plain `Button` after `.buttonStyle(.plain)`, a row that acts on a click through `RowActivation`.
/// A screen never sets a cursor; it composes these blocks. `PointerCursorPolicyTests` fails when a block forgets.
///
/// Enabled and clickable: the pointing hand. Disabled: the default arrow, even inside a row that is a pointing hand. A text
/// field keeps the I-beam, because it never goes through this modifier.
///
///     Button(action: select) { label }
///         .buttonStyle(.plain)
///         .pointerCursor()
extension View {
    func pointerCursor() -> some View {
        modifier(PointerCursor())
    }
}

private struct PointerCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.pointerStyle(isEnabled ? .link : .default)
    }
}

extension PointerStyle {
    /// The system's not-allowed cursor, for a logo that is not a toggle (V5-R25). It goes through the same pointer system as
    /// `.link` so the nearest style wins inside a clickable row; pushing an `NSCursor` would fight the row's pointing hand.
    static let notAllowed: PointerStyle = {
        let cursor = NSCursor.operationNotAllowed
        let size = cursor.image.size
        let hotSpot = UnitPoint(x: cursor.hotSpot.x / max(size.width, 1), y: cursor.hotSpot.y / max(size.height, 1))
        return .image(Image(nsImage: cursor.image), hotSpot: hotSpot)
    }()
}
