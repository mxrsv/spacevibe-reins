import SwiftUI

/// One choice of a `ScopePicker`. `id` is the caller's key for it; Rules uses nil for Global.
struct ScopeOption: Hashable {
    let id: String?
    let label: String
}

/// The scope menu of the Loadout and Rules toolbars: Global or one discovered project. 28 pt like every control, filled with
/// the control ground and no outline. A menu in the app; headless screenshots cannot draw one, so they get the closed label.
struct ScopePicker: View {
    let options: [ScopeOption]
    let current: ScopeOption
    let minWidth: CGFloat
    let onSelect: (ScopeOption) -> Void
    @Environment(\.isShotRendering) private var isShotRendering
    @Environment(\.controlGround) private var ground

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
            .spaceVibeFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityLabel("Scope")
            .accessibilityValue(current.label)
        }
    }

    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        return HStack(spacing: Space.s8) {
            Text(current.label).lineLimit(1)
            Spacer(minLength: 0)
            Chevron(.upDown).foregroundStyle(Palette.textTertiary)
        }
        .spaceVibeText(.body, tone: .primary)
        .padding(.leading, Space.s12)
        .padding(.trailing, Space.s8)
        .frame(minWidth: minWidth, alignment: .leading)
        .fixedSize()
        .frame(height: Metrics.controlHeight)
        .background(shape.fill(ground.fill))
        .contentShape(shape)
    }
}
