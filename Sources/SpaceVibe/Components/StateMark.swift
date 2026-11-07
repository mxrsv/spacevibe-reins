import SwiftUI

/// A state glyph: beside a card's or a band's title, and in a row's warning slot (V5-R14). The triangle in the warn tone
/// (needs a look) or the danger tone (cannot run), the neutral clock (unmeasurable, stale, newly added) or the lock
/// (plugin-owned). `label` is what VoiceOver reads, so the colour never carries the state alone (V5-R43).
struct StateMark: Equatable {
    enum Kind {
        case warn, danger, clock, lock
    }

    let kind: Kind
    let label: String

    init(_ kind: Kind, label: String) {
        self.kind = kind
        self.label = label
    }

    var glyph: ContentGlyph {
        switch kind {
        case .warn, .danger: .warning
        case .clock: .clock
        case .lock: .lock
        }
    }

    var color: Color {
        switch kind {
        case .warn: Palette.warn
        case .danger: Palette.bad
        case .clock, .lock: Palette.fg3
        }
    }
}

/// A `StateMark` drawn as its glyph, 16 by default.
struct StateMarkIcon: View {
    let mark: StateMark
    var size: IconSize = .control

    var body: some View {
        SpaceVibeIcon(content: mark.glyph, size: size, ink: mark.color, label: mark.label)
    }
}

/// The age of a stale reading at a band's right end (V5-R73): the neutral clock and "read 8 h ago", 12 `fg3`, 4 apart.
struct StaleNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: Metrics.StaleNote.spacing) {
            SpaceVibeIcon(content: .clock, ink: Palette.fg3)
            Text(text).spaceVibeText(.meta, tone: .tertiary).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
