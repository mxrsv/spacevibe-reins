import SwiftUI

/// Pointer and keyboard states a gallery specimen draws without a pointer or a key press: the headless shots cannot hover or
/// focus, and the gallery shows every state at once. A block reads it beside its own `onHover` and focus state; only
/// `Gallery/` sets it, so a screen never draws a state it is not in (the mock's `.is-hover` and `.is-focus`).
struct SpecimenInteraction: OptionSet {
    let rawValue: Int

    static let hover = SpecimenInteraction(rawValue: 1 << 0)
    static let focus = SpecimenInteraction(rawValue: 1 << 1)
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct SpecimenInteractionKey: EnvironmentKey {
    static let defaultValue: SpecimenInteraction = []
}

extension EnvironmentValues {
    var specimenInteraction: SpecimenInteraction {
        get { self[SpecimenInteractionKey.self] }
        set { self[SpecimenInteractionKey.self] = newValue }
    }
}

extension View {
    /// Draws the blocks inside as hovered or focused (gallery specimens only).
    func specimen(_ states: SpecimenInteraction) -> some View {
        environment(\.specimenInteraction, states)
    }
}
