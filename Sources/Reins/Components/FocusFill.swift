import SwiftUI

extension View {
    /// The one visible focus: a `sel` fill over the view's shape, never an outline or ring (D57). Drawn over the view, so
    /// it shows on a view with an opaque fill too and deepens a hovered or selected one. For custom focusable views that
    /// track their own focus (`@FocusState`) for something else too (`Row`, `SegmentedControl`); apply it together with
    /// `.focusEffectDisabled()` so the system ring does not add one. Anything else: use `reinsFocusable`.
    func focusFill(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.sel)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Focus state plus the one Reins focus fill, for a custom control that needs nothing else from its focus.
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
            .focusFill(focused, cornerRadius: cornerRadius)
            .onAppear { if focusOnAppear { focused = true } }
    }
}
