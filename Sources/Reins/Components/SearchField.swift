import SwiftUI

/// The entry point to the command palette in the top bar: looks like a search field, acts as a button. 28 pt high, filled with
/// the control ground and no outline; its key cap sits on it as on a card.
struct SearchField: View {
    let placeholder: String
    let shortcut: String
    /// The shortcut as VoiceOver should say it ("Command K").
    let spokenShortcut: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.controlGround) private var ground

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: Space.s8) {
                Image(systemName: "magnifyingglass").imageScale(.small).accessibilityHidden(true)
                Text(placeholder).lineLimit(1)
                Spacer(minLength: 0)
                Kbd(shortcut).controlGround(.card)
            }
            .reinsText(.body, tone: .tertiary)
            .padding(.leading, Space.s8)
            .padding(.trailing, Space.s4)
            .frame(width: Metrics.topBarSearchWidth, height: Metrics.controlHeight)
            .background(shape.fill(hovering ? Palette.surfaceRaised : ground.fill))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .reinsFocusable(cornerRadius: Metrics.fieldRadius)
        .onHover { hovering = $0 }
        .accessibilityLabel(placeholder)
        .accessibilityHint(spokenShortcut)
    }
}
