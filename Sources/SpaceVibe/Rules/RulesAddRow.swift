import SwiftUI

/// The add-rule row: a text field, the verdict and Add. The shape is checked as you submit; the engine's message
/// (a duplicate, a project that is gone) shows under the field. Rule text is never logged.
struct RulesAddRow: View {
    @Bindable var model: RulesModel
    @FocusState private var fieldFocused: Bool

    static let placeholder = "Bash(npm test *)"

    var body: some View {
        GroupedList {
            VStack(alignment: .leading, spacing: Space.s6) {
                HStack(spacing: Rhythm.tools) {
                    TextInputField(
                        label: "Rule", placeholder: Self.placeholder, text: $model.draft, code: true,
                        invalid: model.addError != nil, focused: $fieldFocused, onSubmit: model.submitDraft
                    )
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
                        .reinsText(.caption, tone: .danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(.horizontal, Metrics.rowHorizontalPadding)
            .padding(.vertical, Metrics.rowVerticalPadding)
            .frame(minHeight: Metrics.rowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: model.addFocusToken) { _, _ in fieldFocused = true }
        .onChange(of: model.draft) { _, _ in model.addError = nil }
    }
}
