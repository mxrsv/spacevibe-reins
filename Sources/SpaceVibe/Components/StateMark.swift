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
        ReinsIcon(content: mark.glyph, size: size, ink: mark.color, label: mark.label)
    }
}
