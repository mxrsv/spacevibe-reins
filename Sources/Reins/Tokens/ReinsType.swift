import CoreText
import SwiftUI

/// A text role: one Inter weight at one of the three sizes, its line box on the 4 pt grid, its tracking, and whether it is a
/// machine string. Spec: `docs/specs/2026-11-03-reins-design-language.md` (Typography). A view takes a role with
/// `.reinsText(_:tone:)`; it never builds a font itself, so changing a role here restyles every screen.
///
/// Hierarchy inside one size comes from weight and tone, not size: 12, 14 and 16 are only a step of 1.14 apart.
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
    let ctFont: CTFont

    init(size: CGFloat, weight: InterFont.Weight, lineBox: CGFloat, trackingEm: CGFloat = 0, code: Bool = false, tabular: Bool = false) {
        self.size = size
        self.weight = weight
        self.lineBox = lineBox
        self.trackingEm = trackingEm
        self.code = code
        self.tabular = tabular
        ctFont = InterFont.font(weight, size: size, code: code, tabular: tabular)
    }

    var font: Font { Font(ctFont) }
    var tracking: CGFloat { trackingEm * size }
    /// Ascent, descent and leading of the face at this size.
    var naturalLineHeight: CGFloat { CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont) }
    /// What SwiftUI adds between lines so that every line takes `lineBox`.
    var lineSpacing: CGFloat { max(0, lineBox - naturalLineHeight) }

    func weight(_ weight: InterFont.Weight) -> ReinsType {
        ReinsType(size: size, weight: weight, lineBox: lineBox, trackingEm: trackingEm, code: code, tabular: tabular)
    }

    /// Second lines, column labels, hints, notes, counts.
    static let caption = ReinsType(size: 12, weight: .regular, lineBox: 16)
    /// Section rows, note headings.
    static let captionStrong = ReinsType(size: 12, weight: .semibold, lineBox: 16)
    /// Tags and key caps.
    static let label = ReinsType(size: 12, weight: .medium, lineBox: 16)
    /// Buttons, chips, segments, fields, the sidebar, numbers in cells.
    static let body = ReinsType(size: 14, weight: .regular, lineBox: 20, trackingEm: -0.006)
    /// Banner titles, the primary button, empty-state titles.
    static let bodyStrong = ReinsType(size: 14, weight: .semibold, lineBox: 20, trackingEm: -0.006)
    /// Row names.
    static let rowTitle = ReinsType(size: 14, weight: .medium, lineBox: 20, trackingEm: -0.006)
    /// The page title and card titles. The palette's input uses it at `.regular`.
    static let title = ReinsType(size: 16, weight: .semibold, lineBox: 24, trackingEm: -0.011)
    /// The command palette's input.
    static let paletteInput = ReinsType(size: 16, weight: .regular, lineBox: 24, trackingEm: -0.011)
    /// A command, path or key on a second line.
    static let code = ReinsType(size: 12, weight: .regular, lineBox: 16, code: true)
    /// The muted folder before a file name in a path title.
    static let codeBody = ReinsType(size: 14, weight: .regular, lineBox: 20, trackingEm: -0.006, code: true)
    /// A row name that is a machine string: a failed command, a rule pattern, a file name.
    static let codeTitle = ReinsType(size: 14, weight: .medium, lineBox: 20, trackingEm: -0.006, code: true)
    /// A number in a column: runs, cost.
    static let number = ReinsType(size: 14, weight: .regular, lineBox: 20, trackingEm: -0.006, tabular: true)
    /// A count that must stand out (a skill that never ran).
    static let numberStrong = ReinsType(size: 14, weight: .semibold, lineBox: 20, trackingEm: -0.006, tabular: true)
    /// A count beside a label or in a column of counts (sidebar, chips, group headers).
    static let count = ReinsType(size: 12, weight: .regular, lineBox: 16, tabular: true)
    static let countStrong = ReinsType(size: 12, weight: .semibold, lineBox: 16, tabular: true)
    /// The one exception to 12/14/16: a single leading number per Tokens card.
    static let figure = ReinsType(size: 24, weight: .semibold, lineBox: 32, trackingEm: -0.01, tabular: true)
    /// The other exception (v3): the share left on the Limits page, one at a time. The line box is the face's own height at 72.
    static let display = ReinsType(size: 72, weight: .semibold, lineBox: 88, trackingEm: -0.03, tabular: true)
    /// SF Symbol size for an empty state's icon. Not a text role.
    static let symbolLarge = ReinsType(size: 24, weight: .regular, lineBox: 32)
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
