import SwiftUI

/// One section on the Settings rail: its icon (24) above its name (`label`), 96 x 60, radius 8. Like a sidebar item, the
/// chosen one changes only its fill (`surface` on the well) and its tone; the others fill with `hover` under the pointer.
struct RailTab: View {
    let title: String
    let icon: PageGlyph
    let isActive: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        Button(action: select) {
            VStack(spacing: Space.s4) {
                PageIcon(icon, size: .large)
                Text(title).reinsText(.label)
            }
            .foregroundStyle(isActive ? TextTone.primary.color : TextTone.secondary.color)
            .frame(width: Metrics.railTabWidth, height: Metrics.railTabHeight)
            .background(shape.fill(isActive ? Palette.surface : (hovering ? Palette.hover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .reinsFocusable(cornerRadius: Metrics.controlRadius)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
