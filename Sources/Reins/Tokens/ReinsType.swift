import CoreText
import Foundation
import SwiftUI

/// A text role: one Inter weight at one size, its line box on the 4 pt grid, its tracking, and whether it is a machine
/// string. Spec: `docs/specs/2026-11-03-reins-design-language.md` (Typography). A view takes a role with
/// `.reinsText(_:tone:)`; it never builds a font itself, so changing a role here restyles every screen.
///
/// Hierarchy inside one size comes from weight and tone, not size: 12, 14 and 16 are only a step of 1.14 apart. The Font
/// size setting moves all three by 1 pt (`TypeScale`); the line boxes stay, so the layout keeps its rhythm.
struct ReinsType {
    let size: CGFloat
    let weight: InterFont.Weight
    /// Height of one line, like CSS `line-height`.
    let lineBox: CGFloat
    /// Tracking in em; Inter wants a little less space as it grows.
    let trackingEm: CGFloat
    /// A command, path, key or pattern: `ss02` and `zero` on.
    let code: Bool
    /// Digits of one width, for numbers that line up down a column.
    let tabular: Bool
    /// The v5 roles' `cv11` and `ss03` (`InterFont`).
    let stylistic: Bool
    let ctFont: CTFont

    init(size: CGFloat, weight: InterFont.Weight, lineBox: CGFloat, trackingEm: CGFloat = 0, code: Bool = false, tabular: Bool = false,
         stylistic: Bool = false) {
        self.size = size
        self.weight = weight
        self.lineBox = lineBox
        self.trackingEm = trackingEm
        self.code = code
        self.tabular = tabular
        self.stylistic = stylistic
        ctFont = InterFont.font(weight, size: size, code: code, tabular: tabular, stylistic: stylistic)
    }

    var font: Font { Font(ctFont) }
    var tracking: CGFloat { trackingEm * size }
    /// Ascent, descent and leading of the face at this size.
    var naturalLineHeight: CGFloat { CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont) }
    /// What SwiftUI adds between lines so that every line takes `lineBox`.
    var lineSpacing: CGFloat { max(0, lineBox - naturalLineHeight) }

    func weight(_ weight: InterFont.Weight) -> ReinsType {
        ReinsType(size: size, weight: weight, lineBox: lineBox, trackingEm: trackingEm, code: code, tabular: tabular, stylistic: stylistic)
    }

    /// One role at a Font size step, by default the current one (`TypeScale`): 12, 14 and 16 move by the step, `scales:
    /// false` keeps a size. Reading `TypeScale.shared.step` here ties the calling view body to the setting. Roles are cached
    /// per step, so a body never builds a CTFont. Tests pass `step` instead of changing the shared one.
    static func role(size: CGFloat, scales: Bool = true, step: CGFloat = TypeScale.shared.step, weight: InterFont.Weight, lineBox: CGFloat,
                     trackingEm: CGFloat = 0, code: Bool = false, tabular: Bool = false, stylistic: Bool = false) -> ReinsType {
        let key = RoleKey(size: size + (scales ? step : 0), weight: weight, lineBox: lineBox, trackingEm: trackingEm, code: code, tabular: tabular,
                          stylistic: stylistic)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        let made = ReinsType(size: key.size, weight: weight, lineBox: lineBox, trackingEm: trackingEm, code: code, tabular: tabular,
                             stylistic: stylistic)
        cache[key] = made
        return made
    }

    private struct RoleKey: Hashable {
        let size: CGFloat
        let weight: InterFont.Weight
        let lineBox: CGFloat
        let trackingEm: CGFloat
        let code: Bool
        let tabular: Bool
        let stylistic: Bool
    }

    private static var cache: [RoleKey: ReinsType] = [:]
    private static let cacheLock = NSLock()

    /// Second lines, column labels, hints, notes, counts.
    static var caption: ReinsType { role(size: 12, weight: .regular, lineBox: 16) }
    /// Section rows, note headings.
    static var captionStrong: ReinsType { role(size: 12, weight: .semibold, lineBox: 16) }
    /// Tags and key caps.
    static var label: ReinsType { role(size: 12, weight: .medium, lineBox: 16) }
    /// Buttons, chips, segments, fields, the sidebar, numbers in cells.
    static var body: ReinsType { role(size: 14, weight: .regular, lineBox: 20, trackingEm: -0.006) }
    /// Banner titles, the primary button, empty-state titles.
    static var bodyStrong: ReinsType { role(size: 14, weight: .semibold, lineBox: 20, trackingEm: -0.006) }
    /// Row names.
    static var rowTitle: ReinsType { role(size: 14, weight: .medium, lineBox: 20, trackingEm: -0.006) }
    /// The page title and card titles. The palette's input uses it at `.regular`.
    static var title: ReinsType { role(size: 16, weight: .semibold, lineBox: 24, trackingEm: -0.011) }
    /// The command palette's input.
    static var paletteInput: ReinsType { role(size: 16, weight: .regular, lineBox: 24, trackingEm: -0.011) }
    /// A command, path or key on a second line.
    static var code: ReinsType { role(size: 12, weight: .regular, lineBox: 16, code: true) }
    /// The muted folder before a file name in a path title.
    static var codeBody: ReinsType { role(size: 14, weight: .regular, lineBox: 20, trackingEm: -0.006, code: true) }
    /// A row name that is a machine string: a failed command, a rule pattern, a file name.
    static var codeTitle: ReinsType { role(size: 14, weight: .medium, lineBox: 20, trackingEm: -0.006, code: true) }
    /// A number in a column: runs, cost.
    static var number: ReinsType { role(size: 14, weight: .regular, lineBox: 20, trackingEm: -0.006, tabular: true) }
    /// A count that must stand out (a skill that never ran).
    static var numberStrong: ReinsType { role(size: 14, weight: .semibold, lineBox: 20, trackingEm: -0.006, tabular: true) }
    /// A count beside a label or in a column of counts (sidebar, chips, group headers).
    static var count: ReinsType { role(size: 12, weight: .regular, lineBox: 16, tabular: true) }
    static var countStrong: ReinsType { role(size: 12, weight: .semibold, lineBox: 16, tabular: true) }
    /// The one exception to 12/14/16: a single leading number per Tokens card.
    static var figure: ReinsType { role(size: 24, scales: false, weight: .semibold, lineBox: 32, trackingEm: -0.01, tabular: true) }
    /// The other exception (v3): the share left on the Limits page, one at a time. The line box is the face's own height at 72.
    static var display: ReinsType { role(size: 72, scales: false, weight: .semibold, lineBox: 88, trackingEm: -0.03, tabular: true) }

    // v5 roles (spec, "Type"): only the v5 build behind `SPACEVIBE_UI_V5` uses them. Every one carries the mock body's
    // features (`cv11`, `ss03`, tabular figures) and moves with the Font size setting. The spec's table maps 12 and 14 to
    // `caption`, `label` and `body`; `meta`, `metaLabel` and `field` are those sizes with the v5 features, so a v5 page never
    // mixes the two shapes of the a.
    private static func v5(_ size: CGFloat, _ weight: InterFont.Weight, _ lineBox: CGFloat, trackingEm: CGFloat = 0) -> ReinsType {
        role(size: size, weight: weight, lineBox: lineBox, trackingEm: trackingEm, tabular: true, stylistic: true)
    }

    /// A tab's count and a filter count, 10 pt in a 16 pt circle (the mock's 10/1; one line, so the box is the face's).
    static var micro: ReinsType { v5(10, .medium, 12) }
    /// Secondary meta, chart axis labels.
    static var small: ReinsType { v5(11, .regular, 16) }
    /// Section and sidebar group labels, key caps, menu headings.
    static var smallLabel: ReinsType { v5(11, .medium, 16) }
    /// Captions, a row's secondary text, CLI status rows, the status bar.
    static var meta: ReinsType { v5(12, .regular, 16) }
    /// Controls, menus and filter chips at 12.
    static var metaLabel: ReinsType { v5(12, .medium, 16) }
    /// Body text in sentences and a count in a row.
    static var prose: ReinsType { v5(13, .regular, 20) }
    /// A row's name (450).
    static var rowName: ReinsType { v5(13, .book, 20) }
    /// Buttons and inactive tab labels.
    static var control: ReinsType { v5(13, .medium, 20) }
    /// The active tab's label and a band's label.
    static var controlStrong: ReinsType { v5(13, .semibold, 20) }
    /// The command palette's field.
    static var field: ReinsType { v5(14, .regular, 20) }
    /// A card's title.
    static var cardTitle: ReinsType { v5(16, .semibold, 24, trackingEm: -0.01) }
    /// The Skills pane's heading, a share in a row, a stat figure.
    static var heading: ReinsType { v5(20, .semibold, 28, trackingEm: -0.01) }
    /// The Answer sentence and the pane's meter count: 28/32 as the mock renders it, pending open question 1. Inter's
    /// own height at 28 is above 32, so lines of a wrapped sentence sit at the face's height (risk H4).
    static var answer: ReinsType { v5(28, .semibold, 32, trackingEm: -0.02) }
}

/// Text colours by meaning. Views pick a tone, never a `Palette` colour, so the palette can change in one place.
enum TextTone {
    case primary, secondary, tertiary, accent, onAccent, inverse, danger, warn, success, claude, codex

    var color: Color {
        switch self {
        case .primary: Palette.text
        case .secondary: Palette.textSecondary
        case .tertiary: Palette.textTertiary
        case .accent: Palette.accent
        case .onAccent: Palette.onAccent
        case .inverse: Palette.background
        case .danger: Palette.dangerInk
        case .warn: Palette.warnInk
        case .success: Palette.successInk
        case .claude: Palette.claudeInk
        case .codex: Palette.codexInk
        }
    }
}

extension View {
    /// The role's font, tracking and line spacing; with `tone`, its colour too (without, the colour is inherited).
    func reinsText(_ role: ReinsType, tone: TextTone? = nil) -> some View {
        modifier(RoleText(role: role, tone: tone))
    }
}

private struct RoleText: ViewModifier {
    let role: ReinsType
    let tone: TextTone?

    @ViewBuilder
    func body(content: Content) -> some View {
        let styled = content.font(role.font).tracking(role.tracking).lineSpacing(role.lineSpacing)
        if let tone { styled.foregroundStyle(tone.color) } else { styled }
    }
}

extension Text {
    /// The `Text`-returning form, for concatenation (`Text(a).reinsText(.code) + Text(b).reinsText(.codeTitle)`).
    func reinsText(_ role: ReinsType, tone: TextTone? = nil) -> Text {
        let styled = font(role.font).tracking(role.tracking)
        guard let tone else { return styled }
        return styled.foregroundStyle(tone.color)
    }
}
