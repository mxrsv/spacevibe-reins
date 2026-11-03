import SwiftUI

extension View {
    /// The one visible focus ring: 2 pt in the accent colour. For custom focusable views that track their own
    /// focus (`@FocusState`) for something else too (`Row`, `SegmentedControl`); apply it together with
    /// `.focusEffectDisabled()` so the system ring does not double it. Anything else: use `reinsFocusable`.
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

    /// Focus state plus the one Reins focus ring, for a custom control that needs nothing else from its focus.
    /// `focusOnAppear` takes the focus when the view appears, for the default button of a confirmation.
    func reinsFocusable(cornerRadius: CGFloat, focusOnAppear: Bool = false) -> some View {
        modifier(ReinsFocusable(cornerRadius: cornerRadius, focusOnAppear: focusOnAppear))
    }
}

private struct ReinsFocusable: ViewModifier {
    let cornerRadius: CGFloat
    let focusOnAppear: Bool
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .focusEffectDisabled()
            .focusRing(focused, cornerRadius: cornerRadius)
            .onAppear { if focusOnAppear { focused = true } }
    }
}
