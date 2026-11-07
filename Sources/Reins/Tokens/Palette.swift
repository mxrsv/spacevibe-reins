import AppKit
import SwiftUI

/// One colour token's value in each appearance: sRGB `0xRRGGBB` and an alpha. `Palette` builds every colour from one of
/// these, and `ContrastTests` and `HuePolicyTests` read the same values, so a test checks the token and not a copy.
struct ColorValue: Sendable {
    let light: UInt32
    let dark: UInt32
    var lightAlpha: Double = 1
    var darkAlpha: Double = 1

    var color: Color { Color(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha) }
}

/// The values behind `Palette`, under the token names of the v5 spec's token table
/// (`docs/specs/2026-11-06-reins-design-language-v5.md`, read from the frozen mock's `system/shared.css`). Values changed
/// from the spec to pass `ContrastTests` say so on their line: each is a departure the owner sees at the final eye task.
///
/// Rules the names encode:
/// - Surfaces, lines and text greys are neutral (R, G and B within 4 of each other in dark, 8 in light).
/// - `ok`, `warn` and `bad` mark state only. The categories, the CLI colours (Claude clay, Codex in the text colour) and
///   the accent sit outside their hue families (`HuePolicyTests`).
/// - Translucent tokens are composited over their real ground before a contrast check.
enum PaletteValue {
    // Surfaces, darkest to lightest in dark
    /// The sidebar and the window.
    static let bgSide = ColorValue(light: 0xF4F4F5, dark: 0x0B0C0D)
    /// The search field's ground.
    static let bgApp = ColorValue(light: 0xF4F4F5, dark: 0x0F1011)
    /// The content panel, the Skills list and pane.
    static let bgPanel = ColorValue(light: 0xFFFFFF, dark: 0x131416)
    /// Cards, buttons, meters, chips.
    static let bgRaise = ColorValue(light: 0xFBFBFB, dark: 0x191A1D)
    /// The verdict box.
    static let bgSunk = ColorValue(light: 0xF6F6F7, dark: 0x0E0F10)
    /// Menu, popover, toast, bottom bar, palette, dialog.
    static let bgPop = ColorValue(light: 0xFFFFFF, dark: 0x1B1C1F)
    /// A band header.
    static let bgBand = ColorValue(light: 0xEEEFF2, dark: 0x1B1C20)
    /// A hovered band header: `bgBand` mixed with `fg`, 4% (dark) and 3% (light). Departure: the mock mixes 8%, which puts
    /// `fg3` (the band's count) at 4.38:1 in dark and 4.16:1 in light; in light no mix above 4% keeps it at 4.5:1.
    static let bgBandHover = ColorValue(light: 0xE8E9EC, dark: 0x242528)
    /// A focused band header (D57: the hover fill one step stronger), 6% (dark) and 4% (light). Hovered and focused together
    /// take this one fill, never two stacked.
    static let bgBandFocus = ColorValue(light: 0xE6E7EA, dark: 0x28292D)

    // Lines and fills over a surface
    static let hair = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.075)
    /// Control outline, overlay edge, chart base.
    static let hair2 = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.14, darkAlpha: 0.12)
    static let rowDivider = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.065, darkAlpha: 0.055)
    /// The 1 px top-edge highlight of panels, cards, buttons and overlays.
    static let hi = ColorValue(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.9, darkAlpha: 0.05)
    static let hover = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.035, darkAlpha: 0.04)
    /// The current row, the current sidebar item, and the focus fill (D57).
    static let sel = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.055, darkAlpha: 0.065)
    static let track = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.065, darkAlpha: 0.07)
    static let trackHi = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.12)
    static let kbdBg = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.035, darkAlpha: 0.06)
    static let kbdBorder = ColorValue(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.10)
    static let scrim = ColorValue(light: 0x141418, dark: 0x000000, lightAlpha: 0.25, darkAlpha: 0.5)

    // Text
    static let fg = ColorValue(light: 0x1B1C1F, dark: 0xF2F3F4)
    /// Departure, light: spec `#5E626A` reads 4.20:1 as an inactive tab's count on its circle; `#595D65` reads 4.54:1.
    static let fg2 = ColorValue(light: 0x595D65, dark: 0xA3A7AE)
    /// Departure, both: the spec's `#6B7078` (dark) and `#8B8F97` (light) carry text at 2.85:1 and 2.61:1 at worst (the
    /// current row of a menu or the palette, the current sidebar item). Raised to the least lightness change, hue and
    /// chroma kept, that reads 4.5:1 on every text ground (risk H5): `#8D929A` dark, `#646870` light. It now sits close to
    /// `fg2` (1.30:1 dark, 1.18:1 light, from 2.06:1 and 1.89:1).
    static let fg3 = ColorValue(light: 0x646870, dark: 0x8D929A)
    /// Disabled and separators; never text a user must read.
    static let fg4 = ColorValue(light: 0xB7BAC0, dark: 0x4A4E55)

    // Accent: shade 1 of the mock (D10, D68); shades 2 and 3 stay in the spec for the eye pick.
    /// Indicators and fills: the current row's bar, a picked checkbox, Activity's active tab, the system tint.
    static let accent = ColorValue(light: 0x2563D9, dark: 0x4F86F7)
    /// The accent as text (links, `Show more`, `Clear`, the toast's `Undo`). Departure, dark: shade 1 reads 4.12:1 as
    /// `Undo` on a focused toast button (`sel` over `bgPop`) and 4.44:1 hovered; `#568EFF`, a step lighter on the same hue,
    /// reads 4.54:1. Kept apart from `accent` so the shade-1 fills keep their look.
    static let accentText = ColorValue(light: 0x2563D9, dark: 0x568EFF)
    /// A solid accent fill under white text (primary button, switch, the product mark). Departure, both: white on the
    /// accent reads 3.45:1 in dark; this darker step of the same hue keeps 4.5:1 at rest and with the hover brightening.
    static let accentSolid = ColorValue(light: 0x1E5CD2, dark: 0x2A5DCB)
    /// A picked row and a filter count: the accent at 10% (light) and 16% (dark).
    static let accentBg = ColorValue(light: 0x2563D9, dark: 0x4F86F7, lightAlpha: 0.10, darkAlpha: 0.16)
    static let onAccent = ColorValue(light: 0xFFFFFF, dark: 0xFFFFFF)

    // State only
    /// Departure, light: spec `#2F9E6B` reads 2.89:1 as a mark on a current row; `#2A9B68` reads 3:1.
    static let ok = ColorValue(light: 0x2A9B68, dark: 0x4CB782)
    /// Departure, light: spec `#C4811A` reads 2.76:1 as a mark on a current row and 2.81:1 on a band header. U2's `#BD7A0B`
    /// read 3:1 there, then 2.85:1 on a focused band (`bgBandFocus`) and 2.62:1 as a bar on the track of a current row; `#B26F00` (OKLCH
    /// lightness lowered, chroma and hue kept to the sRGB gamut) reads 3:1 on both.
    static let warn = ColorValue(light: 0xB26F00, dark: 0xE2A33C)
    /// Departure, both, hue only (OKLCH lightness and chroma kept): the spec's `#E5604F` (dark) and `#D2442F` (light) sit
    /// 9° and 7° of hue from Claude's clay, inside the ±20° danger family (`HuePolicyTests`). Moved redder to hue 15:
    /// clay is now 24° and 23° away, `catRule` 25°.
    static let bad = ColorValue(light: 0xD13F58, dark: 0xE45C6F)
    /// The solid danger button's fill under white text (Stop). Departure, both: white on `bad` reads 3.43:1 in dark; this
    /// darker step of the same hue keeps 4.5:1 at rest and with the hover brightening.
    static let badSolid = ColorValue(light: 0xBE2C49, dark: 0xB8334C)
    /// The off dot of a CLI status row.
    static let mute = ColorValue(light: 0x7A7F88, dark: 0x8A8F98)
    /// The cut-out inside a verdict glyph.
    static let onVerdict = ColorValue(light: 0xFFFFFF, dark: 0x0F1011)

    // The two CLIs (identity only)
    static let claude = ColorValue(light: 0xC65F3E, dark: 0xD97757)
    /// Codex is the text colour (the blue `#1596D6` of 2026-11-05 is gone).
    static let codex = ColorValue(light: 0x1B1C1F, dark: 0xF2F3F4)

    // Category colours: set 1 of the mock (D68). They tell categories apart and nothing else.
    static let catSkill = ColorValue(light: 0x7C5CE0, dark: 0xA78BFA)
    static let catSubagent = ColorValue(light: 0xB83CC8, dark: 0xD974E0)
    static let catHook = ColorValue(light: 0x0E8BA8, dark: 0x35C0DA)
    /// Departure, both, hue only: moved from the spec's `#E8709F` / `#D2487F` (hue 357 and 359) to hue 350, so it keeps
    /// more than 20° from `bad` after `bad` moved to hue 15.
    static let catRule = ColorValue(light: 0xCC4A91, dark: 0xE471AC)

    // The active tab's text and count. Spec: the category colour in dark, mixed 68% with black in light. Departure: in
    // dark the colour reads 4.2:1 to 4.4:1 on its chip and 2.1:1 on its count circle, so the text is mixed with white
    // (category share 0.79 to 0.91) and the count further (0.08 to 0.33, close to `fg`: no tinted count reads 4.5:1 on a
    // 40% circle); in light the count is mixed 51% to 54% with black. Activity's tabs use the accent's pair.
    static let catSkillInk = ColorValue(light: 0x543F98, dark: 0xB7A0FB)
    static let catSkillCountInk = ColorValue(light: 0x423177, dark: 0xE8E1FE)
    static let catSubagentInk = ColorValue(light: 0x7D2988, dark: 0xE190E6)
    static let catSubagentCountInk = ColorValue(light: 0x5E1F66, dark: 0xF5D9F7)
    static let catHookInk = ColorValue(light: 0x0A5F72, dark: 0x47C6DD)
    static let catHookCountInk = ColorValue(light: 0x074857, dark: 0xEFFAFC)
    static let catRuleInk = ColorValue(light: 0x8B3263, dark: 0xEA8FBD)
    static let catRuleCountInk = ColorValue(light: 0x6A264B, dark: 0xF7D6E7)
    static let accentInk = ColorValue(light: 0x194394, dark: 0x7BA4F9)
    static let accentCountInk = ColorValue(light: 0x143575, dark: 0xC0D3FC)

    // Overlay shadows (v5): popover and toast; palette and dialog.
    static let shadowPop = ColorValue(light: 0x000000, dark: 0x000000, lightAlpha: 0.4, darkAlpha: 0.4)
    static let shadowDialog = ColorValue(light: 0x000000, dark: 0x000000, lightAlpha: 0.5, darkAlpha: 0.5)

    // Kept for the screens not yet rebuilt; the cut-over (X1) deletes each one no rebuilt page uses.
    /// Text in a state or CLI colour: the fill's hue at the old ramp (light L 0.38 / C 0.08, dark L 0.80 / C 0.07),
    /// raised where needed until it reads 4.5:1 on its tint and on the surfaces.
    static let successInk = ColorValue(light: 0x0E4F32, dark: 0x97CCAD)
    static let warnInk = ColorValue(light: 0x5D3A03, dark: 0xD8B88B)
    static let dangerInk = ColorValue(light: 0x662E34, dark: 0xE7ACAF)
    static let claudeInk = ColorValue(light: 0x663121, dark: 0xE6AF9D)
    /// Codex's colour is the text colour, so its ink is too.
    static let codexInk = fg
    /// The text colour at 6%: the empty Limits ruler cells on a selected tile.
    static let trackOnSelection = ColorValue(light: 0x1B1C1F, dark: 0xF2F3F4, lightAlpha: 0.06, darkAlpha: 0.06)
    /// The old overlays' shadow (palette, confirmation, toast).
    static let overlayShadow = ColorValue(light: 0x111111, dark: 0x000000, lightAlpha: 0.22, darkAlpha: 0.5)

    /// The share of its fill a tint takes (sidebar tiles, banners, state tiles).
    static let tintAlpha = 0.15
    static func tint(of fill: ColorValue) -> ColorValue {
        ColorValue(light: fill.light, dark: fill.dark, lightAlpha: tintAlpha, darkAlpha: tintAlpha)
    }

    // The Reins mark (`Resources/AppIcon.svg`): the same in both appearances, like the app icon.
    static let markGround = ColorValue(light: 0x050608, dark: 0x050608)
    static let markInk = ColorValue(light: 0xF4F5F7, dark: 0xF4F5F7)
    /// Monochrome brand artwork, independent of chart and status hues.
    static let brandMonochrome = ColorValue(light: 0x000000, dark: 0xFFFFFF)
}

/// A tab chip's fills, each a share of its colour: `fg` for an inactive tab, the category (or the accent on Activity) for
/// the active one (spec, "Category colours").
enum TabChipAlpha {
    static let rest = 0.07
    static let hover = 0.12
    static let active = 0.26
    static let activeFocus = 0.34
    /// The count circle: `fg` on an inactive tab, the category on the active one.
    static let count = 0.12
    static let activeCount = 0.40
}

/// The colours views use. Every value is dynamic: it follows the window's appearance, which the shell overrides from
/// `AppearanceStore`, so a view never branches on dark or light. Values live in `PaletteValue`.
enum Palette {
    // v5 tokens, by their spec names
    static let bgSide = PaletteValue.bgSide.color
    static let bgApp = PaletteValue.bgApp.color
    static let bgPanel = PaletteValue.bgPanel.color
    static let bgRaise = PaletteValue.bgRaise.color
    static let bgSunk = PaletteValue.bgSunk.color
    static let bgPop = PaletteValue.bgPop.color
    static let bgBand = PaletteValue.bgBand.color
    static let bgBandHover = PaletteValue.bgBandHover.color
    static let bgBandFocus = PaletteValue.bgBandFocus.color
    static let hair = PaletteValue.hair.color
    static let hair2 = PaletteValue.hair2.color
    static let rowDivider = PaletteValue.rowDivider.color
    static let hi = PaletteValue.hi.color
    static let hover = PaletteValue.hover.color
    static let sel = PaletteValue.sel.color
    static let track = PaletteValue.track.color
    static let trackHi = PaletteValue.trackHi.color
    static let kbdBg = PaletteValue.kbdBg.color
    static let kbdBorder = PaletteValue.kbdBorder.color
    static let scrim = PaletteValue.scrim.color
    static let fg = PaletteValue.fg.color
    static let fg2 = PaletteValue.fg2.color
    static let fg3 = PaletteValue.fg3.color
    static let fg4 = PaletteValue.fg4.color
    static let accent = PaletteValue.accent.color
    static let accentText = PaletteValue.accentText.color
    static let accentSolid = PaletteValue.accentSolid.color
    static let accentBg = PaletteValue.accentBg.color
    static let onAccent = PaletteValue.onAccent.color
    static let ok = PaletteValue.ok.color
    static let warn = PaletteValue.warn.color
    static let bad = PaletteValue.bad.color
    static let badSolid = PaletteValue.badSolid.color
    static let mute = PaletteValue.mute.color
    static let onVerdict = PaletteValue.onVerdict.color
    static let claude = PaletteValue.claude.color
    static let codex = PaletteValue.codex.color
    static let catSkill = PaletteValue.catSkill.color
    static let catSubagent = PaletteValue.catSubagent.color
    static let catHook = PaletteValue.catHook.color
    static let catRule = PaletteValue.catRule.color
    static let catSkillInk = PaletteValue.catSkillInk.color
    static let catSkillCountInk = PaletteValue.catSkillCountInk.color
    static let catSubagentInk = PaletteValue.catSubagentInk.color
    static let catSubagentCountInk = PaletteValue.catSubagentCountInk.color
    static let catHookInk = PaletteValue.catHookInk.color
    static let catHookCountInk = PaletteValue.catHookCountInk.color
    static let catRuleInk = PaletteValue.catRuleInk.color
    static let catRuleCountInk = PaletteValue.catRuleCountInk.color
    static let accentInk = PaletteValue.accentInk.color
    static let accentCountInk = PaletteValue.accentCountInk.color
    static let shadowPop = PaletteValue.shadowPop.color
    static let shadowDialog = PaletteValue.shadowDialog.color

    // Old names: the screens not yet rebuilt keep them, with the v5 value of the token that replaces each (D53, spec C3).
    // The cut-over (X1) moves their last uses to the v5 names and deletes them.
    static let background = bgApp
    /// The ground of the content area and the sidebar.
    static let well = bgSide
    /// A card on the well.
    static let surface = bgPanel
    /// A control or tag inside a card.
    static let surfaceRaised = bgRaise
    /// `hair2`: the spec has `hair` replace `border` and `hair2` extend it; every use of `border` is a `hair2` role
    /// (an overlay's edge, a field's outline), and its old light value `#DADADA` was black at 14.5%.
    static let border = hair2
    /// `hair`: between two rows of a card, and between the sidebar and the content area.
    static let divider = hair
    static let selection = sel
    static let text = fg
    static let textSecondary = fg2
    static let textTertiary = fg3
    static let success = ok
    static let danger = bad
    static let overlay = scrim

    static let successInk = PaletteValue.successInk.color
    static let warnInk = PaletteValue.warnInk.color
    static let dangerInk = PaletteValue.dangerInk.color
    static let claudeInk = PaletteValue.claudeInk.color
    static let codexInk = PaletteValue.codexInk.color
    static let trackOnSelection = PaletteValue.trackOnSelection.color
    static let overlayShadow = PaletteValue.overlayShadow.color

    // Tints behind sidebar tiles, banners and state tiles: the fill at 15%; text on them uses the Ink twin.
    static let claudeTint = PaletteValue.tint(of: PaletteValue.claude).color
    static let codexTint = PaletteValue.tint(of: PaletteValue.codex).color
    static let successTint = PaletteValue.tint(of: PaletteValue.ok).color
    static let warnTint = PaletteValue.tint(of: PaletteValue.warn).color
    static let dangerTint = PaletteValue.tint(of: PaletteValue.bad).color

    static let markGround = PaletteValue.markGround.color
    static let markInk = PaletteValue.markInk.color
    static let brandMonochrome = PaletteValue.brandMonochrome.color
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
