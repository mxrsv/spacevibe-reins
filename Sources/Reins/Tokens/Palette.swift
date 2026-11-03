import AppKit
import SwiftUI

/// Design tokens for both appearances. Every value is a dynamic color: it follows the window's
/// appearance, which the shell overrides from `AppearanceStore`, so a view never branches on dark or light.
///
/// Where the values come from: the approved "Matrix" mock (`mock-shell/reins.css`) and the superseded
/// Electron renderer's `src/index.css` are written in oklch. Each value below is that oklch colour
/// converted to sRGB with the standard OKLab -> linear sRGB matrices plus the sRGB transfer curve, clamped
/// to the gamut, then rounded to 8 bits. Where the Electron CSS refined a mock value for contrast, the
/// refined one is used (dark `textTertiary` 0.73 instead of 0.68, dark `danger` 0.76 instead of 0.72).
/// Alpha colours keep their alpha, so they composite over whichever surface they sit on.
///
/// Rules the names encode:
/// - `claude` and `codex` are the two CLI colours. They are fills (bars, dots). Text in those colours
///   uses the `...Ink` twin, which is darker in light mode so it keeps 4.5:1 on its own tint.
/// - `success`, `warn` and `danger` mark state only; never decoration.
/// - A card is a `surface` block on the `well`, with no border; rows inside it are separated by `divider`. Only overlays
///   (palette, confirmation, toast) keep a `border` and a shadow.
///
/// Contrast measured for these values (WCAG, text on its real background): `text` 12.8 to 17.3,
/// `textSecondary` 5.9 to 9.6, `textTertiary` 4.4 to 8.1 (dark) and 4.9 to 6.0 (light; the one pair under
/// 4.5 is tertiary on a selected row in dark, 4.4 since the v3 surface), tag text on `surfaceRaised` 5.1 to 7.7, every `...Ink`
/// on its 15 percent tint 5.1 to 6.3, white on `accentSolid` 4.9 (dark) and 6.4 (light), the focus ring
/// 6.1 to 7.5 on every surface. `border` is decoration (1.3 to 1.4 against its surface), not a control
/// boundary on its own.
enum Palette {
    // Surfaces
    static let background = Color(light: 0xF8FAFE, dark: 0x121721)
    /// The ground of the content area and the sidebar: one step darker than a card in light, the background itself in dark,
    /// so cards read as blocks. Reuses existing values (light `surfaceRaised`, dark `background`).
    static let well = Color(light: 0xF0F4FA, dark: 0x121721)
    static let surface = Color(light: 0xFFFFFF, dark: 0x232B38)
    static let surfaceRaised = Color(light: 0xF0F4FA, dark: 0x2C3544)
    static let border = Color(light: 0xD3D8E0, dark: 0x363D4B, darkAlpha: 0.7)
    /// The text colour at 8%: between two rows of a card, and between the sidebar and the content area.
    static let divider = Color(light: 0x141B26, dark: 0xF0F2F6, lightAlpha: 0.08, darkAlpha: 0.08)

    // Interaction
    static let hover = Color(light: 0xD7DEEC, dark: 0x262E3D, lightAlpha: 0.6, darkAlpha: 0.55)
    static let selection = Color(light: 0x4164ED, dark: 0x496CEF, lightAlpha: 0.14, darkAlpha: 0.28)
    static let accent = Color(light: 0x3250D8, dark: 0x82A5FF)
    static let accentSolid = Color(light: 0x3250D8, dark: 0x4164ED)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0xFFFFFF)

    // Text
    static let text = Color(light: 0x141B26, dark: 0xF0F2F6)
    static let textSecondary = Color(light: 0x474D58, dark: 0xB2B8C1)
    static let textTertiary = Color(light: 0x5D646F, dark: 0xA2A8B2)

    // The two CLIs: fill and text-safe ink
    static let claude = Color(light: 0xCD632D, dark: 0xF69A65)
    static let claudeInk = Color(light: 0x933D08, dark: 0xF69A65)
    static let codex = Color(light: 0x008388, dark: 0x4FCDCD)
    static let codexInk = Color(light: 0x006469, dark: 0x4FCDCD)

    // State only
    static let success = Color(light: 0x007840, dark: 0x63D18F)
    static let successInk = Color(light: 0x005F2E, dark: 0x63D18F)
    static let warn = Color(light: 0xCB9317, dark: 0xE7B643)
    static let warnInk = Color(light: 0x7B5200, dark: 0xE7B643)
    static let danger = Color(light: 0xD01C29, dark: 0xFF7F7F)
    static let dangerInk = Color(light: 0xBB061E, dark: 0xFF7F7F)

    // Tints behind tags and banners (a state colour at low alpha; text on top uses the Ink twin)
    static let claudeTint = Color(light: 0xCD632D, dark: 0xF69A65, lightAlpha: 0.15, darkAlpha: 0.15)
    static let codexTint = Color(light: 0x008388, dark: 0x4FCDCD, lightAlpha: 0.15, darkAlpha: 0.15)
    static let successTint = Color(light: 0x007840, dark: 0x63D18F, lightAlpha: 0.15, darkAlpha: 0.15)
    static let warnTint = Color(light: 0xD6A62E, dark: 0xE7B643, lightAlpha: 0.20, darkAlpha: 0.15)
    static let dangerTint = Color(light: 0xD01C29, dark: 0xFF7F7F, lightAlpha: 0.10, darkAlpha: 0.15)

    // Overlays (palette scrim, toast)
    static let overlay = Color(light: 0x11161F, dark: 0x010309, lightAlpha: 0.35, darkAlpha: 0.5)
    static let overlayShadow = Color(light: 0x11161F, dark: 0x010309, lightAlpha: 0.22, darkAlpha: 0.5)
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
