import SwiftUI

/// A one-line text input, 28 pt like every control: the add-rule field. `code` sets it as a machine string; `invalid`
/// turns the border red while the error shows under it. Headless screenshots cannot draw a `TextField`, so they get the
/// text it would show.
struct TextInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var code = false
    var invalid = false
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        Group {
            if isShotRendering {
                Text(text.isEmpty ? placeholder : text)
                    .foregroundStyle((text.isEmpty ? TextTone.tertiary : TextTone.primary).color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(TextTone.tertiary.color))
                    .textFieldStyle(.plain)
                    .foregroundStyle(TextTone.primary.color)
                    .focused(focused)
                    .onSubmit(onSubmit)
                    .autocorrectionDisabled()
            }
        }
        .reinsText(code ? .code : .body)
        .lineLimit(1)
        .padding(.horizontal, Space.s8)
        .frame(height: Metrics.controlHeight)
        .background(shape.fill(Palette.surface))
        .overlay(shape.strokeBorder(invalid ? Palette.danger : Palette.border, lineWidth: 1))
        .focusRing(focused.wrappedValue, cornerRadius: Metrics.controlRadius)
        .accessibilityLabel(label)
        .accessibilityValue(text)
    }
}
