import SwiftUI

/// One entry in the sidebar list (a tab, or the Limits page): icon, title, an optional mark right after the title (Limits'
/// stale clock), and a count on the right (in the danger tone when it is an alert). 48 pt high in the `title` role in every
/// state, radius 8, 16 pt inside at both ends; the icon is 22 pt in the secondary tone. The active entry changes only its
/// fill (`surface` on the well), never its text, weight or icon.
struct SidebarItem<Mark: View>: View {
    let title: String
    let icon: SpaceVibeGlyph
    var count: Int?
    var alert = false
    /// What VoiceOver says for the count ("2 sessions running"); the number when nil.
    var spokenCount: String?
    let isActive: Bool
    let mark: Mark
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        Button(action: select) {
            HStack(spacing: Space.s8) {
                SpaceVibeIcon(icon, size: .sidebar).foregroundStyle(TextTone.secondary.color)
                Text(title)
                mark
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)").spaceVibeText(alert ? .bodyStrong : .body, tone: alert ? .danger : .tertiary)
                }
            }
            .spaceVibeText(.title, tone: .primary)
            .padding(.horizontal, Metrics.sidebarItemPadding)
            .frame(height: Metrics.sidebarItemHeight)
            .background(shape.fill(isActive ? Palette.surface : (hovering ? Palette.hover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .spaceVibeFocusable(cornerRadius: Metrics.controlRadius)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(count.map { "\(title), \(spokenCount ?? String($0))" } ?? title)
    }
}

extension SidebarItem where Mark == EmptyView {
    init(title: String, icon: SpaceVibeGlyph, count: Int? = nil, alert: Bool = false, spokenCount: String? = nil, isActive: Bool,
         select: @escaping () -> Void) {
        self.init(title: title, icon: icon, count: count, alert: alert, spokenCount: spokenCount, isActive: isActive,
                  mark: EmptyView(), select: select)
    }
}

extension SidebarItem {
    init(title: String, icon: SpaceVibeGlyph, isActive: Bool, @ViewBuilder mark: () -> Mark, select: @escaping () -> Void) {
        self.init(title: title, icon: icon, count: nil, alert: false, spokenCount: nil, isActive: isActive, mark: mark(),
                  select: select)
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
