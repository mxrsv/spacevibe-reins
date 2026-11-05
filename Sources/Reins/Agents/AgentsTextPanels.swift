import ReinsCore
import SwiftUI

/// Rules (both CLIs): the instruction file in the Markdown editor, Edit or Preview. A `@path` line opens that file in the
/// same panel with a crumb back; an edit to either file joins the one draft.
struct InstructionsPanel: View {
    @Bindable var model: AgentsModel
    let base: InstructionFile

    var body: some View {
        let shown = model.shownImport ?? base
        if model.shownImport != nil {
            Button { model.showImport(nil) } label: {
                HStack(spacing: Space.s4) {
                    Chevron(.left, size: .inline)
                    Text(base.file.lastPathComponent)
                }
            }
            .buttonStyle(.reins(.ghost))
        }
        MarkdownEditor(text: text(shown), isEditing: model.isEditing, openImport: { model.showImport($0) }, startEditing: { model.isEditing = true })
    }

    private func text(_ file: InstructionFile) -> Binding<String> {
        Binding(
            get: { model.draft.text(for: file.file) ?? file.text },
            set: { next in
                if next == file.text {
                    model.draft.remove { if case .text(let url, _) = $0 { return url == file.file } else { return false } }
                } else {
                    model.draft.add(.edit, file.file.lastPathComponent, .text(file: file.file, next))
                }
            }
        )
    }
}

/// Model (both CLIs): a free-text field ("Same as Global (x)" when a project leaves it unset), chips of the models seen in
/// the logs with their session counts, and Codex's reasoning effort.
struct ModelPanel: View {
    @Bindable var model: AgentsModel
    let agent: AgentKind
    let data: ModelData
    @FocusState private var focused: Bool

    var body: some View {
        let current = draftModel ?? data.current ?? ""
        GroupedList {
            CardHeader("Model", detail: agent == .claude ? "model" : "config.toml")
            SettingRow(title: "Model", key: "model", note: data.current == nil && model.currentScope != .global ? "Unset here: uses Global." : nil) {
                TextInputField(label: "Model", placeholder: placeholder, text: modelBinding, code: true, focused: $focused) {}
            }
            if !data.seen.isEmpty {
                SettingRow(title: "Seen in the logs", note: "Sessions per model, from the most recent logs.") {
                    FlowRow {
                        ForEach(data.seen) { seen in
                            FilterChip(seen.model, count: seen.sessions, code: true, isOn: seen.model == current) { set(seen.model) }
                        }
                    }
                }
            }
            if agent == .codex {
                SettingRow(title: "Reasoning effort", key: "model_reasoning_effort") {
                    SegmentedControl(label: "Reasoning effort", options: AgentsWording.efforts.map { SegmentOption($0.title, value: $0.value) },
                                     selection: effortBinding)
                }
            }
        }
    }

    private var placeholder: String {
        if model.currentScope != .global { return "Same as Global (\(data.global ?? "default"))" }
        return "default"
    }

    private var draftModel: String? {
        for item in model.draft.items.reversed() {
            if case .claude(.model(let value)) = item.change { return value ?? "" }
            if case .codex(.model(let value)) = item.change { return value ?? "" }
        }
        return nil
    }

    private var modelBinding: Binding<String> {
        Binding(get: { draftModel ?? data.current ?? "" }, set: { set($0) })
    }

    private func set(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed == (data.current ?? "") {
            model.draft.remove { if case .claude(.model) = $0 { return true } else if case .codex(.model) = $0 { return true } else { return false } }
            return
        }
        let next: String? = trimmed.isEmpty ? nil : trimmed
        let text = "model \u{2192} \(next ?? "unset")"
        model.draft.add(.change, text, agent == .claude ? .claude(.model(next)) : .codex(.model(next)))
    }

    private var effortBinding: Binding<String> {
        Binding(
            get: {
                for item in model.draft.items.reversed() { if case .codex(.reasoningEffort(let value)) = item.change { return value ?? "" } }
                return data.effort ?? ""
            },
            set: { value in
                if value == (data.effort ?? "") {
                    model.draft.remove { if case .codex(.reasoningEffort) = $0 { return true } else { return false } }
                } else {
                    model.draft.add(.change, "model_reasoning_effort \u{2192} \(value)", .codex(.reasoningEffort(value)))
                }
            }
        )
    }
}

/// Advanced (both CLIs): the whole settings file in the code editor, its secrets masked. Syntax only is checked; Save is
/// blocked while the file is invalid, naming the line.
struct AdvancedPanel: View {
    @Bindable var model: AgentsModel
    let masked: MaskedText

    var body: some View {
        CodeEditor(text: binding, problem: model.advancedProblem, hiddenCount: masked.hiddenCount)
        if model.open?.agent == .codex {
            Text("Codex [profiles.*] tables are edited here only.").reinsText(.caption, tone: .tertiary)
        }
    }

    private var binding: Binding<String> {
        Binding(
            get: { model.draft.advancedText ?? masked.text },
            set: { next in
                if next == masked.text {
                    model.draft.remove { if case .advanced = $0 { return true } else { return false } }
                } else {
                    model.draft.add(.edit, model.open?.agent == .codex ? "config.toml" : "settings.json", .advanced(next))
                }
            }
        )
    }
}
