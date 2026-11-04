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
/// The surfaces, borders, hover, dividers and text greys are neutral (R = G = B) since 2026-11-04: the earlier navy tint
/// (`0x121721` and friends) read as a blue cast on every screen. The accent, selection and the CLI and state colours are unchanged.
///
/// Contrast measured for the neutral surfaces (WCAG, text on `well`, `surface` and `surfaceRaised`): `text` 11.1 to 18.4,
/// `textSecondary` 5.9 to 9.3, `textTertiary` 4.9 to 7.2 (dark) and 5.8 to 6.5 (light). The values below this line were
/// measured on the earlier navy surfaces and not repeated: tertiary on a selected row, tag text on `surfaceRaised` 5.1 to 7.7, every `...Ink`
/// on its 15 percent tint 5.1 to 6.3, white on `accentSolid` 4.9 (dark) and 6.4 (light), the focus ring
/// 6.1 to 7.5 on every surface. `border` is decoration (1.3 to 1.4 against its surface), not a control
/// boundary on its own.
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
    static let selection = Color(light: 0x4164ED, dark: 0x496CEF, lightAlpha: 0.14, darkAlpha: 0.28)
    /// The text colour at 14%: a ruler's empty cells on a selected tile, where `surfaceRaised` would read as grey patches.
    static let trackOnSelection = Color(light: 0x141414, dark: 0xF2F2F2, lightAlpha: 0.14, darkAlpha: 0.14)
    static let accent = Color(light: 0x3250D8, dark: 0x82A5FF)
    static let accentSolid = Color(light: 0x3250D8, dark: 0x4164ED)
    /// The primary button and every chosen control (v4): hover lifts the accent, pressed sinks it. The same in both.
    static let accentHover = Color(light: 0x4A6CF0, dark: 0x4A6CF0)
    static let accentPressed = Color(light: 0x2C47C4, dark: 0x2C47C4)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0xFFFFFF)

    // Raised controls (v4, button direction A "Khối có chiều sâu"): a block with a 0.5 pt hairline, a shadow 1 pt down with
    // a 2 pt blur, and a 1 pt highlight along its top edge. Buttons, card buttons, filter chips and the scope picker.
    static let controlFill = Color(light: 0xFFFFFF, dark: 0x3D3D3D)
    static let controlFillHover = Color(light: 0xFAFAFA, dark: 0x454545)
    static let controlFillPressed = Color(light: 0xEBEBEB, dark: 0x323232)
    static let controlHairline = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.16, darkAlpha: 0.7)
    static let controlShadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0.45)
    static let controlHighlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.9, darkAlpha: 0.09)
    /// The primary button's and a chosen control's own top highlight, hairline and shadow (the mock's values: the accent
    /// takes a fainter highlight than a neutral block, and a shadow tinted with it).
    static let accentHighlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.22)
    static let accentHairline = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.25, darkAlpha: 0.25)
    static let accentShadow = Color(light: 0x1E32A0, dark: 0x1E32A0, lightAlpha: 0.35, darkAlpha: 0.35)
    /// Under a chosen segment, which sits inside the sunken track rather than on the well.
    static let chosenShadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.3, darkAlpha: 0.3)
    /// The segmented control's sunken track: in dark a `#1F1F1F` fill below `surface`, laid over the control ground; in light
    /// the ground shows through. `segmentShadow` is its inner shadow, 1 pt down with a 2 pt blur.
    static let segmentTrack = Color(light: 0xFFFFFF, dark: 0x1F1F1F, lightAlpha: 0, darkAlpha: 1)
    static let segmentShadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.35)
    /// Text and icons on a solid state fill (a chosen verdict segment): white on the light success and danger fills,
    /// `#141414` on warn and on every dark fill, where the fills are pale. Each measures at least 4.5:1 (PaletteContrastTests).
    static let onSuccess = Color(light: 0xFFFFFF, dark: 0x141414)
    static let onDanger = Color(light: 0xFFFFFF, dark: 0x141414)
    static let onWarn = Color(light: 0x141414, dark: 0x141414)

    // Text
    static let text = Color(light: 0x141414, dark: 0xF2F2F2)
    static let textSecondary = Color(light: 0x474747, dark: 0xB3B3B3)
    static let textTertiary = Color(light: 0x5E5E5E, dark: 0xA3A3A3)

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
