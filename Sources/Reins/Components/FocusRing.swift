import SwiftUI

extension View {
    /// The one visible focus ring: 2 pt in the accent colour. For custom focusable views that track their own
    /// focus (`@FocusState`); apply it together with `.focusEffectDisabled()` so the system ring does not double it.
    /// `inset` draws the ring inside the bounds, for views inside a clipped group.
    func focusRing(_ isFocused: Bool, cornerRadius: CGFloat, inset: Bool = false) -> some View {
        overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .padding(inset ? 0 : -2)
                    .allowsHitTesting(false)
            }
        }
    }
}
