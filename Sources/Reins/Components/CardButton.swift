import SwiftUI

/// What a card button shows after its name: a count ("11"), a file or model name in the `code` role ("CLAUDE.md"), or
/// nothing (Advanced). `alert` follows the value after a dot in the danger tone ("4 · 1 dead"); `warn` paints the value
/// itself in the warn ink ("Full access", "2 models").
struct CardButtonValue: Equatable {
    enum Style: Equatable {
        case count, code
    }

    let text: String
    var style: Style = .count
    var warn = false
    var alert: String?

    static func count(_ text: String, warn: Bool = false, alert: String? = nil) -> CardButtonValue {
        CardButtonValue(text: text, style: .count, warn: warn, alert: alert)
    }

    static func code(_ text: String, warn: Bool = false) -> CardButtonValue {
        CardButtonValue(text: text, style: .code, warn: warn)
    }
}

/// The agent card's way into a panel (spec v4, "Card button"): a 16 pt page icon, the name in `rowTitle` and its value,
/// 32 pt high (the one exception to the 28 pt control), radius 8. `plain` is a raised neutral block; `ghost` (Advanced) has
/// no fill until hovered. While its panel is open the button takes the accent, with white text and icons.
struct CardButton: View {
    enum Kind {
        case plain, ghost
    }

    let title: String
    let icon: PageGlyph
    var value: CardButtonValue?
    var kind: Kind = .plain
    let isOpen: Bool
    let action: () -> Void

    @Environment(\.forcedControlState) private var forced
    @State private var hovering = false
    @State private var pressing = false

    init(_ title: String, icon: PageGlyph, value: CardButtonValue? = nil, kind: Kind = .plain, isOpen: Bool,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.value = value
        self.kind = kind
        self.isOpen = isOpen
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        let hovered = !isOpen && (hovering || forced == .hover)
        let pressed = !isOpen && (pressing || forced == .pressed)
        Button(action: action) {
            HStack(spacing: Space.s8) {
                PageIcon(icon).foregroundStyle(isOpen ? Palette.onAccent.opacity(0.85) : Palette.textSecondary)
                Text(title).reinsText(.rowTitle).foregroundStyle(isOpen ? Palette.onAccent : (kind == .ghost ? Palette.textSecondary : Palette.text))
                if let value { valueText(value) }
            }
            .lineLimit(1)
            .padding(.leading, Space.s8 + Space.s2)
            .padding(.trailing, Space.s12)
            .frame(height: Metrics.cardButtonHeight)
            .background {
                if isOpen {
                    ControlBlock(look: .chosen)
                } else if kind == .plain {
                    ControlBlock(hovered: hovered, pressed: pressed)
                } else {
                    shape.fill(pressed ? Palette.track : (hovered ? Palette.hover : .clear))
                }
            }
            .offset(y: pressed && kind == .plain ? Metrics.controlPressedOffset : 0)
            .contentShape(shape)
        }
        .buttonStyle(PressReporting(pressing: $pressing))
        .onHover { hovering = $0 }
        .reinsFocusable(cornerRadius: Metrics.controlRadius)
        .focusRing(forced == .focus, cornerRadius: Metrics.controlRadius)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityHint(isOpen ? "Closes the panel" : "Opens the panel")
    }

    private func valueText(_ value: CardButtonValue) -> some View {
        let tone: Color = isOpen ? Palette.onAccent.opacity(0.85) : (value.warn ? Palette.warnInk : Palette.textTertiary)
        return HStack(spacing: Space.s4) {
            Text(value.text).reinsText(value.style == .code ? .code : .count).foregroundStyle(tone)
            if let alert = value.alert {
                Text("\u{00B7}").reinsText(.count).foregroundStyle(tone)
                Text(alert).reinsText(.countStrong).foregroundStyle(isOpen ? Palette.onAccent : Palette.dangerInk)
            }
        }
    }

    private var spoken: String {
        guard let value else { return title }
        return [title, value.text, value.alert].compactMap { $0 }.joined(separator: ", ")
    }
}
