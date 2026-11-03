import SwiftUI

/// One tab in the sidebar: icon, title, and a count on the right (in the danger tone when it is an alert). 32 pt high,
/// radius 8; the active tab is semibold on the selection tint.
struct SidebarItem: View {
    let title: String
    let systemImage: String
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
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .frame(width: Metrics.sidebarIconWidth)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)").reinsText(alert ? .countStrong : .count, tone: alert ? .danger : (isActive ? .secondary : .tertiary))
                }
            }
            .reinsText(isActive ? .bodyStrong : .body, tone: isActive ? .primary : .secondary)
            .padding(.horizontal, Space.s8)
            .frame(height: Metrics.sidebarItemHeight)
            .background(shape.fill(isActive ? Palette.selection : (hovering ? Palette.hover : .clear)))
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
    /// The sidebar column: fixed width, the sidebar colour and its trailing hairline, room for the traffic lights on top.
    func sidebarSurface() -> some View {
        padding(.top, Metrics.trafficLightsInset)
            .padding(.horizontal, Space.s8)
            .padding(.bottom, Space.s12)
            .frame(width: Metrics.sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(Palette.sidebar)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Palette.border).frame(width: 1).accessibilityHidden(true)
            }
    }
}
