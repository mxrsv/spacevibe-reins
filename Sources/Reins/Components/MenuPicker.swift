import SwiftUI

/// One choice of a `MenuPicker`: its value, its words, an optional line under it and whether it is a risky choice.
struct MenuOption<Value: Hashable>: Hashable {
    let value: Value
    let title: String
    var detail: String?
    /// Bypass, `danger-full-access`, `never`: the closed picker reads in the warn tone with its icon.
    var warn = false
    /// A heading above this option in the menu ("Your profiles", "Built in").
    var section: String?
    /// Set as a machine string (a profile or model name).
    var code = false
}

/// A menu that picks one value (Default mode, a hook's event, a profile, `extends`): the scope picker's raised block with
/// the current title and the selector chevron. A menu in the app; headless shots get the closed label. A risky current
/// choice reads in the warn ink with a warning icon.
struct MenuPicker<Value: Hashable>: View {
    let label: String
    let options: [MenuOption<Value>]
    let selection: Value
    var minWidth: CGFloat = Metrics.scopePickerMinWidth
    var fill = false
    let onSelect: (Value) -> Void

    @Environment(\.isShotRendering) private var isShotRendering
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        if isShotRendering {
            closed
        } else {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    if let section = option.section {
                        if index > 0 { Divider() }
                        Text(section)
                    }
                    Toggle(option.title, isOn: Binding(get: { option.value == selection }, set: { _ in onSelect(option.value) }))
                }
            } label: {
                closed
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .onHover { hovering = $0 }
            .reinsFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityLabel(label)
            .accessibilityValue(current?.title ?? "")
        }
    }

    private var current: MenuOption<Value>? { options.first { $0.value == selection } }

    private var closed: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        let warn = current?.warn ?? false
        return HStack(spacing: Space.s8) {
            if warn { PageIcon(.warning, size: .inline, ink: Palette.warnInk) }
            Text(current?.title ?? "")
                .reinsText(current?.code == true ? .codeTitle : .body)
                .foregroundStyle(warn ? Palette.warnInk : Palette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isEnabled { Chevron(.upDown, size: .inline).foregroundStyle(Palette.textTertiary) }
        }
        .padding(.leading, Space.s12)
        .padding(.trailing, Space.s8)
        .frame(minWidth: minWidth, maxWidth: fill ? .infinity : nil, alignment: .leading)
        .frame(height: Metrics.controlHeight)
        .background { ControlBlock(hovered: isEnabled && hovering) }
        .contentShape(shape)
    }
}

/// The two-option choice cards of the both-models state ("Keep sandbox_mode", "Keep the profile"): a raised `surfaceRaised`
/// block with a title and a line under it; the chosen one takes the selection tint with a 1.5 pt accent ring.
struct ChoiceCard: View {
    let title: String
    let detail: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title).reinsText(.rowTitle, tone: .primary)
                Text(detail).reinsText(.caption, tone: .tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.s12 + Space.s2)
            .padding(.vertical, Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(isOn ? Palette.selection : Palette.surfaceRaised))
            .overlay(shape.strokeBorder(isOn ? Palette.accent : .clear, lineWidth: Metrics.choiceRingWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .reinsFocusable(cornerRadius: Metrics.controlRadius)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A verdict or decision tag that opens a menu (spec, Interface: Permissions): "Move to" each other choice, then Remove.
/// The tag keeps its look with a small chevron; headless shots get the tag alone.
struct TagMenu: View {
    let title: String
    var tone: TagTone = .neutral
    /// The other choices, by title, and what each does.
    let moves: [(title: String, action: () -> Void)]
    var remove: (() -> Void)?

    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        if isShotRendering {
            Tag(title, tone: tone)
        } else {
            Menu {
                ForEach(Array(moves.enumerated()), id: \.offset) { _, move in
                    Button("Move to \(move.title)", action: move.action)
                }
                if let remove {
                    Divider()
                    Button("Remove", role: .destructive, action: remove)
                }
            } label: {
                Tag(title, tone: tone)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .reinsFocusable(cornerRadius: Metrics.tagRadius)
            .accessibilityLabel("\(title), change")
        }
    }
}
