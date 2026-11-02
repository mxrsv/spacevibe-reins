import SwiftUI

/// Left column: room for the traffic lights, the tabs with their counts, and a footer with scan status and the
/// theme toggle. Tabs are plain buttons; `⌘1`..`⌘3` (View menu) switch too.
struct SidebarView: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Metrics.trafficLightsInset)
            VStack(spacing: 2) {
                ForEach(shell.tabs, id: \.id) { tab in
                    SidebarItem(tab: tab, isActive: tab.id == shell.activeID) { shell.select(tab.id) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let status = shell.statusMessage {
                    Text(status)
                        .font(ReinsFont.small)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer(minLength: 0)
                ThemeToggle()
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: Metrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.border).frame(width: 1).accessibilityHidden(true)
        }
    }
}

private struct SidebarItem: View {
    let tab: any ReinsTab
    let isActive: Bool
    let select: () -> Void

    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        let badge = tab.badge
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .imageScale(.medium)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(tab.title)
                Spacer(minLength: 0)
                if let badge {
                    Text("\(badge.value)")
                        .font(badge.alert ? ReinsFont.smallStrong : ReinsFont.small)
                        .foregroundStyle(badge.alert ? Palette.dangerInk : (isActive ? Palette.textSecondary : Palette.textTertiary))
                }
            }
            .font(isActive ? ReinsFont.bodyStrong : ReinsFont.body)
            .foregroundStyle(isActive ? Palette.text : Palette.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(shape.fill(isActive ? Palette.selection : (hovering ? Palette.hover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .focusRing(focused, cornerRadius: Metrics.controlRadius)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(badge.map { "\(tab.title), \($0.spoken ?? String($0.value))" } ?? tab.title)
    }
}
