import AppKit
import SwiftUI

/// Design tokens for both appearances. Every value is a dynamic color: it follows the window's
/// appearance, which the shell overrides from `AppearanceStore`, so a view never branches on dark or light.
///
/// The 2026-11-05 palette keeps distinct hues in one restrained tonal family, informed by Paradev.
/// Dark identity/state fills start at OKLCH L 0.67 / C 0.12; light fills at L 0.54 / C 0.11.
/// Codex is pinned to Paradev's #1596D6 in both appearances by the owner's 2026-11-05 choice.
/// Light warning is slightly brighter so dark text can also sit on its solid fill. Ink is a separate
/// same-hue ramp (light L 0.38 / C 0.08, dark L 0.80 / C 0.07), not the bar colour reused for text.
/// Values are converted to 8-bit sRGB; tints keep the fill's RGB at 15% alpha.
///
/// Rules the names encode:
/// - `claude` and `codex` are the two CLI colours. They are fills (bars, dots). Text in those colours
///   uses the `...Ink` twin, which is darker in light mode so it keeps 4.5:1 on its own tint.
/// - `success`, `warn` and `danger` mark state only; never decoration.
/// - A card is a `surface` block on the `well`, with no border; rows inside it are separated by `divider`. Only overlays
///   (palette, confirmation, toast) keep a `border` and a shadow.
///
/// Surfaces, borders, hover, dividers and text greys stay neutral (R = G = B). Selection uses a quiet
/// blue tint; its empty ruler cells use less alpha so they do not wash out the filled cells.
/// Contrast must be checked on composited surfaces, including nested sidebar tints and selected tiles.
enum Palette {
    // Surfaces
    static let background = Color(light: 0xF8F8F8, dark: 0x161616)
    /// The ground of the content area and the sidebar: one step darker than a card in light, the background itself in dark,
    /// so cards read as blocks. Reuses existing values (light `surfaceRaised`, dark `background`).
    static let well = Color(light: 0xF2F2F2, dark: 0x161616)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A2A2A)
    static let surfaceRaised = Color(light: 0xF2F2F2, dark: 0x343434)
    /// The empty part of a usage bar (Loadout, Activity). The Limits ruler draws its empty cells in `surfaceRaised`.
    static let track = Color(light: 0xE2E2E2, dark: 0x383838)
    static let border = Color(light: 0xDADADA, dark: 0x3A3A3A, darkAlpha: 0.7)
    /// The text colour at 8%: between two rows of a card, and between the sidebar and the content area.
    static let divider = Color(light: 0x141414, dark: 0xF2F2F2, lightAlpha: 0.08, darkAlpha: 0.08)

    // Interaction
    static let hover = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.07)
    static let selection = Color(light: 0x476EAE, dark: 0x6995DF, lightAlpha: 0.12, darkAlpha: 0.12)
    /// The text colour at 6%: keeps the empty cells distinct without reducing filled-cell contrast on selection.
    static let trackOnSelection = Color(light: 0x141414, dark: 0xF2F2F2, lightAlpha: 0.06, darkAlpha: 0.06)
    static let accent = Color(light: 0x476EAE, dark: 0xA4BFEB)
    static let accentSolid = Color(light: 0x39588A, dark: 0x39588A)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0xFFFFFF)

    // Text
    static let text = Color(light: 0x141414, dark: 0xF2F2F2)
    static let textSecondary = Color(light: 0x474747, dark: 0xB3B3B3)
    static let textTertiary = Color(light: 0x5E5E5E, dark: 0xA3A3A3)

    // The two CLIs: fill and text-safe ink
    static let claude = Color(light: 0xA25834, dark: 0xD17C54)
    static let claudeInk = Color(light: 0x65331B, dark: 0xE5B099)
    static let codex = Color(light: 0x1596D6, dark: 0x1596D6)
    static let codexInk = Color(light: 0x15466A, dark: 0x98C3E8)

    // State only
    static let success = Color(light: 0x2D8152, dark: 0x50AB74)
    static let successInk = Color(light: 0x154F2F, dark: 0x9ACCAA)
    static let warn = Color(light: 0x9F7A26, dark: 0xB78F2F)
    static let warnInk = Color(light: 0x563E00, dark: 0xD3BB8A)
    static let danger = Color(light: 0xA5524D, dark: 0xD5766F)
    static let dangerInk = Color(light: 0x662F2C, dark: 0xE8ADA7)

    // Tints behind marks and banners: the corresponding fill at 15%; text uses the Ink twin.
    static let claudeTint = Color(light: 0xA25834, dark: 0xD17C54, lightAlpha: 0.15, darkAlpha: 0.15)
    static let codexTint = Color(light: 0x1596D6, dark: 0x1596D6, lightAlpha: 0.15, darkAlpha: 0.15)
    static let successTint = Color(light: 0x2D8152, dark: 0x50AB74, lightAlpha: 0.15, darkAlpha: 0.15)
    static let warnTint = Color(light: 0x9F7A26, dark: 0xB78F2F, lightAlpha: 0.15, darkAlpha: 0.15)
    static let dangerTint = Color(light: 0xA5524D, dark: 0xD5766F, lightAlpha: 0.15, darkAlpha: 0.15)

    // The Reins mark (`Resources/AppIcon.svg`): the same in both appearances, like the app icon.
    static let markGround = Color(light: 0x050608, dark: 0x050608)
    static let markInk = Color(light: 0xF4F5F7, dark: 0xF4F5F7)

    // Overlays (palette scrim, toast)
    static let overlay = Color(light: 0x111111, dark: 0x000000, lightAlpha: 0.35, darkAlpha: 0.5)
    static let overlayShadow = Color(light: 0x111111, dark: 0x000000, lightAlpha: 0.22, darkAlpha: 0.5)
}

extension Color {
    /// A colour that resolves per appearance. Hex is 0xRRGGBB in sRGB.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
