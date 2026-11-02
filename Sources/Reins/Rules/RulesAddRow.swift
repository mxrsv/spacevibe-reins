import SwiftUI

/// The add-rule row: a text field, the verdict and Add. The shape is checked as you submit; the engine's message
/// (a duplicate, a project that is gone) shows under the field. Rule text is never logged.
struct RulesAddRow: View {
    @Bindable var model: RulesModel
    @Environment(\.isShotRendering) private var isShotRendering
    @FocusState private var fieldFocused: Bool

    static let placeholder = "Bash(npm test *)"

    var body: some View {
        GroupedList {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    field
                    SegmentedControl(
                        label: "Verdict for the new rule",
                        options: RulesWording.verdicts.map { SegmentOption(RulesWording.title($0), value: $0) },
                        selection: $model.draftVerdict
                    )
                    Button("Add rule") { model.submitDraft() }
                        .buttonStyle(.reins(.normal))
                        .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isWriting || model.snapshot?.problems.isEmpty == false)
                }
                if let error = model.addError {
                    Text(error)
                        .font(ReinsFont.small)
                        .foregroundStyle(Palette.dangerInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 12)
        .onChange(of: model.addFocusToken) { _, _ in fieldFocused = true }
        .onChange(of: model.draft) { _, _ in model.addError = nil }
    }

    @ViewBuilder
    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        Group {
            if isShotRendering {
                // ImageRenderer cannot draw a TextField; draw what it would show.
                Text(model.draft.isEmpty ? Self.placeholder : model.draft)
                    .foregroundStyle(model.draft.isEmpty ? Palette.textTertiary : Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $model.draft, prompt: Text(Self.placeholder).foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.text)
                    .focused($fieldFocused)
                    .onSubmit { model.submitDraft() }
                    .autocorrectionDisabled()
            }
        }
        .font(ReinsFont.mono)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: Metrics.controlHeight)
        .background(shape.fill(Palette.background))
        .overlay(shape.strokeBorder(model.addError == nil ? Palette.border : Palette.danger, lineWidth: 1))
        .focusRing(fieldFocused, cornerRadius: Metrics.controlRadius)
        .accessibilityLabel("Rule")
        .accessibilityValue(model.draft)
    }
}
