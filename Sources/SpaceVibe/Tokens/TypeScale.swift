import Foundation
import Observation

/// Settings > Appearance > Font size. Each step adds or removes 1 pt on every 12, 14 and 16 pt role and every v5 role;
/// line boxes, spacing, icons, `figure` and `display` stay (spec `docs/specs/2026-11-04-reins-settings.md`, Decisions).
enum FontSizeChoice: String, CaseIterable {
    case small
    case standard = "default"
    case large

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        }
    }

    /// Points added to each scaled role.
    var step: CGFloat {
        switch self {
        case .small: -1
        case .standard: 0
        case .large: 1
        }
    }
}

/// The current Font size step for the whole app. `SpaceVibeType` roles read `step`, and a view body that reads a role is
/// observed through it, so changing the setting re-renders exactly the text that uses a role, without a relaunch.
/// Only the app's own `AppearanceStore` and the screenshot runs write it.
@Observable
final class TypeScale {
    static let shared = TypeScale()

    var step: CGFloat = 0

    /// A width measured for text set at `size` (52 for "12,345" in Inter 14): grown in proportion at a larger step, never
    /// narrower than measured, so a smaller step leaves the columns as they are.
    func width(_ measured: CGFloat, at size: CGFloat) -> CGFloat {
        max(measured, (measured * (size + step) / size).rounded(.up))
    }
}
