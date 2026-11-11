import SwiftUI

extension View {
    /// A neutral filled strip inside the control, distinct from selection and clear of its text (D57: no ring).
    /// Reusing `fg` keeps it above 3:1 on neutral, selected and category grounds; solid buttons use `onAccent`.
    /// Never darken the whole control to reach 3:1: that would make secondary text fail 4.5:1.
    func focusFill(_ isFocused: Bool, cornerRadius: CGFloat, onSolid: Bool = false) -> some View {
        modifier(FocusFill(isFocused: isFocused, cornerRadius: cornerRadius, onSolid: onSolid))
    }

    /// Focus state plus the one SpaceVibe focus fill, for a custom control that needs nothing else from its focus.
    /// `focusOnAppear` takes the focus when the view appears, for the default button of a confirmation.
    func spaceVibeFocusable(cornerRadius: CGFloat, focusOnAppear: Bool = false, onSolid: Bool = false) -> some View {
        modifier(SpaceVibeFocusable(cornerRadius: cornerRadius, focusOnAppear: focusOnAppear, onSolid: onSolid))
    }
}

private struct FocusFill: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    let onSolid: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isFocused && isEnabled {
                Capsule()
                    .fill(onSolid ? Palette.onAccent : Palette.fg)
                    .frame(height: Space.s2)
                    .padding(.horizontal, max(cornerRadius, Space.s4))
                    .padding(.bottom, Space.s2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct SpaceVibeFocusable: ViewModifier {
    let cornerRadius: CGFloat
    let focusOnAppear: Bool
    let onSolid: Bool
    @Environment(\.specimenInteraction) private var specimen
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .focusEffectDisabled()
            .focusFill(focused || specimen.contains(.focus), cornerRadius: cornerRadius, onSolid: onSolid)
            .onAppear { if focusOnAppear { focused = true } }
    }
}
