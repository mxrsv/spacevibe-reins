import SwiftUI

/// One tab in the sidebar: icon, title, and a count on the right (in the danger tone when it is an alert). 48 pt high in
/// the `title` role in every state, radius 8, 16 pt inside at both ends; the icon is 22 pt in the secondary tone. The
/// active tab changes only its fill (`surface` on the well), never its text, weight or icon.
struct SidebarItem: View {
    let title: String
    let icon: ReinsGlyph
    var count: Int?
    var alert = false
    /// What VoiceOver says for the count ("2 sessions running"); the number when nil.
    var spokenCount: String?
    let isActive: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        Button(action: select) {
            HStack(spacing: Space.s8) {
                ReinsIcon(icon, size: .sidebar).foregroundStyle(TextTone.secondary.color)
                Text(title)
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)").reinsText(alert ? .bodyStrong : .body, tone: alert ? .danger : .tertiary)
                }
            }
            .reinsText(.title, tone: .primary)
            .padding(.horizontal, Metrics.sidebarItemPadding)
            .frame(height: Metrics.sidebarItemHeight)
            .background(shape.fill(isActive ? Palette.surface : (hovering ? Palette.hover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .reinsFocusable(cornerRadius: Metrics.controlRadius)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(count.map { "\(title), \(spokenCount ?? String($0))" } ?? title)
    }
}

extension View {
    /// The sidebar column: fixed width on the same `well` as the content area, one 1 pt divider on its trailing edge, room
    /// for the traffic lights on top.
    func sidebarSurface() -> some View {
        padding(.top, Metrics.trafficLightsInset)
            .padding(.horizontal, Space.s8)
            .padding(.bottom, Space.s12)
            .frame(width: Metrics.sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(Palette.well)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Palette.divider).frame(width: 1).accessibilityHidden(true)
            }
    }
}
