import SwiftUI

/// One choice of a `ScopePicker`. `id` is the caller's key for it; Rules uses nil for Global.
struct ScopeOption: Hashable {
    let id: String?
    let label: String
}

/// The scope menu of the Loadout and Rules toolbars and the Agents panels: Global or one discovered project. 28 pt like
/// every control, a raised block (spec v4). Disabled, it keeps its block and drops the chevron. A menu in the app; headless
/// screenshots cannot draw one, so they get the closed label.
struct ScopePicker: View {
    let options: [ScopeOption]
    let current: ScopeOption
    let minWidth: CGFloat
    let onSelect: (ScopeOption) -> Void
    @Environment(\.isShotRendering) private var isShotRendering
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forcedControlState) private var forced
    @State private var hovering = false

    var body: some View {
        if isShotRendering {
            label
        } else {
            Menu {
                // A toggle per option: the menu draws its own checkmark beside the current one.
                ForEach(options, id: \.id) { option in
                    Toggle(option.label, isOn: Binding(get: { option.id == current.id }, set: { _ in onSelect(option) }))
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { hovering = $0 }
            .reinsFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityLabel("Scope")
            .accessibilityValue(current.label)
        }
    }

    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        let pressed = isEnabled && forced == .pressed
        return HStack(spacing: Space.s8) {
            Text(current.label).lineLimit(1)
            Spacer(minLength: 0)
            if isEnabled { Chevron(.upDown, size: .inline).foregroundStyle(Palette.textTertiary) }
        }
        .reinsText(.body, tone: .primary)
        .padding(.leading, Space.s12)
        .padding(.trailing, Space.s8)
        .frame(minWidth: minWidth, alignment: .leading)
        .fixedSize()
        .frame(height: Metrics.controlHeight)
        .background {
            ControlBlock(hovered: isEnabled && (hovering || forced == .hover), pressed: pressed)
        }
        .offset(y: pressed ? Metrics.controlPressedOffset : 0)
        .contentShape(shape)
        .focusRing(forced == .focus, cornerRadius: Metrics.controlRadius)
    }
}
