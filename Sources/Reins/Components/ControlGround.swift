import SwiftUI

/// What a control sits on. Controls have no outline (spec v3, Controls), so their fill is what sets them off: `surface` on
/// the page's well, `surfaceRaised` inside a card. A card, a dialog and the search field set `.card` for what they hold;
/// everything else is on the well.
enum ControlGround {
    case well, card

    var fill: Color { self == .well ? Palette.surface : Palette.surfaceRaised }
}

// Written out: the `@Entry` macro needs SwiftUI's macro plugin, which the Command Line Tools do not ship.
private struct ControlGroundKey: EnvironmentKey {
    static let defaultValue = ControlGround.well
}

extension EnvironmentValues {
    var controlGround: ControlGround {
        get { self[ControlGroundKey.self] }
        set { self[ControlGroundKey.self] = newValue }
    }
}

extension View {
    /// The ground the controls inside this view sit on.
    func controlGround(_ ground: ControlGround) -> some View {
        environment(\.controlGround, ground)
    }
}
