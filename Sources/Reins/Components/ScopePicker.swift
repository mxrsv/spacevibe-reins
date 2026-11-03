import SwiftUI

/// One choice of a `ScopePicker`. `id` is the caller's key for it; Rules uses nil for Global.
struct ScopeOption: Hashable {
    let id: String?
    let label: String
}

/// The scope menu of the Loadout and Rules toolbars: Global or one discovered project. 28 pt like every control. A menu in
/// the app; headless screenshots cannot draw one, so they get the closed label.
struct ScopePicker: View {
    let options: [ScopeOption]
    let current: ScopeOption
    let minWidth: CGFloat
    let onSelect: (ScopeOption) -> Void
    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        if isShotRendering {
            label
        } else {
            Menu {
                ForEach(options, id: \.id) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        if option.id == current.id { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                    }
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .reinsFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityLabel("Scope")
            .accessibilityValue(current.label)
        }
    }

    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        return HStack(spacing: Space.s8) {
            Text(current.label).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(Palette.textTertiary).accessibilityHidden(true)
        }
        .reinsText(.body, tone: .primary)
        .padding(.leading, Space.s12)
        .padding(.trailing, Space.s8)
        .frame(minWidth: minWidth, alignment: .leading)
        .fixedSize()
        .frame(height: Metrics.controlHeight)
        .background(shape.fill(Palette.surface))
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .contentShape(shape)
    }
}
