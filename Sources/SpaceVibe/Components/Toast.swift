import SwiftUI

/// The toast itself: inverted surface, message, its action (or a dismiss button when it has none). 40 pt: 6 around a 28 pt button.
struct ToastView: View {
    let toast: Toast
    let run: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.s12) {
            if toast.tone == .danger {
                SpaceVibeIcon(.warning)
            }
            Text(toast.message).spaceVibeText(.body)
            if let action = toast.action {
                Button(action: run) {
                    HStack(spacing: Space.s6) {
                        SpaceVibeIcon(action.icon)
                        Text(action.title)
                    }
                    .spaceVibeText(.bodyStrong)
                }
                .buttonStyle(.spaceVibe(.inverse))
            } else {
                Button(action: dismiss) { SpaceVibeIcon(.close) }
                    .buttonStyle(.spaceVibe(.inverse))
                    .accessibilityLabel("Dismiss")
            }
        }
        .foregroundStyle(TextTone.inverse.color)
        .padding(.leading, Space.s16)
        .padding(.trailing, Space.s6)
        .padding(.vertical, Space.s6)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.text))
        .shadow(color: Palette.overlayShadow, radius: Metrics.toastShadowRadius, y: Metrics.toastShadowOffset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.message)
    }
}

/// The v5 toast (V5-R38, V5-R59): 40 high on `bgPop` with a `hair2` edge, radius 8, the top-edge highlight and the pop
/// shadow; the message in 13/20 `fg`, 12 before its one action, a 24-high accent button (`Undo` with its `Z` cap). Without an
/// action it is the message alone (the Stop toast has no Undo). A danger toast leads with the danger triangle, so the tone
/// is not colour alone. Placed by the content panel 24 from the right and 48 above the bottom (104 over the bottom bar);
/// it stays 5 s (`ToastCenter`).
struct ToastBar: View {
    let toast: Toast
    let run: () -> Void

    var body: some View {
        HStack(spacing: Metrics.Toast.spacing) {
            if toast.tone == .danger {
                StateMarkIcon(mark: StateMark(.danger, label: "Error"))
            }
            Text(toast.message).spaceVibeText(.prose, tone: .primary).lineLimit(1)
            if let action = toast.action {
                Button(action: run) {
                    HStack(spacing: Metrics.Toast.actionSpacing) {
                        Text(action.title)
                        if let key = action.keyCap { KeyCap(key) }
                    }
                }
                .buttonStyle(ToastActionStyle())
                .focusEffectDisabled()
            }
        }
        .padding(.leading, Metrics.Toast.leading)
        .padding(.trailing, Metrics.Toast.trailing)
        .frame(height: Metrics.Toast.height)
        .blockSurface(Palette.bgPop, edge: Palette.hair2)
        .overlayShadow(.pop)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.message)
    }
}

/// The toast's action: 24 high, 8 at the sides, 13/20 500 in `accentText`; hovered `hover`, focused `sel`.
private struct ToastActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledLabel(configuration: configuration) }

    private struct StyledLabel: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.specimenInteraction) private var specimen
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.Radius.control, style: Metrics.Radius.cornerStyle)
            let fill: Color = isFocused || specimen.contains(.focus) || configuration.isPressed ? Palette.sel
                : (hovering || specimen.contains(.hover) ? Palette.hover : .clear)
            configuration.label
                .spaceVibeText(.control)
                .foregroundStyle(Palette.accentText)
                .padding(.horizontal, Metrics.Toast.actionPadding)
                .frame(height: Metrics.Toast.actionHeight)
                .background(shape.fill(fill))
                .focusFill(isFocused || specimen.contains(.focus), cornerRadius: Metrics.Radius.control)
                .contentShape(shape)
                .pointerCursor()
                .onHover { hovering = $0 }
        }
    }
}
