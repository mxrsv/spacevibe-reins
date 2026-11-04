import ReinsCore
import SwiftUI

/// Permissions for Codex at Global (spec, Interface: Permissions, Codex; plan A9): the status sentence recomputed from the
/// draft, the both-models card when both are set, How Codex runs (approval, and either the sandbox or the active
/// profile), and the command rules. Everything shown is the masked file with the draft applied.
struct CodexPermissionsPanel: View {
    @Bindable var model: AgentsModel
    let saved: CodexConfig
    let masked: String
    let rules: [CodexRulesFile]
    @FocusState private var rootFocused: Bool
    @FocusState private var ruleFocused: Bool

    var body: some View {
        let shown = draftConfig
        let sentence = AgentsWording.codexSentence(shown)
        StatusLead(tone: sentence.warn ? .warn : .success, sentence: sentence.text, detail: detail(shown))
        if saved.permissionModel == .both { BothModelsCard(model: model, config: shown) }
        GroupedList {
            CardHeader("How Codex runs", detail: "config.toml")
            SettingRow(title: "Asks before acting", key: "approval_policy", note: shown.approvalPolicy == "never" ? AgentsWording.neverWarning : nil,
                       warn: shown.approvalPolicy == "never") {
                SegmentedControl(label: "Asks before acting", options: AgentsWording.approvals.map {
                    SegmentOption($0.title, value: $0.value, tone: $0.warn ? .warn : nil)
                }, selection: choice(shown.approvalPolicy ?? "on-request", key: .approval))
            }
            if shown.permissionModel == .profiles || (saved.permissionModel == .both && model.draft.items.contains { $0.change == .codex(.keepModel(.profiles)) }) {
                CodexProfileEditor(model: model, config: shown)
            } else {
                legacy(shown)
            }
        }
        CodexCommandRules(model: model, rules: rules)
    }

    private enum Key { case approval, sandbox }

    /// The saved file with the draft applied, read the way Codex reads it; the saved one when the draft cannot apply.
    var draftConfig: CodexConfig {
        guard !model.draft.codexChanges.isEmpty,
              let text = try? CodexConfigEdit.apply(model.draft.codexChanges, to: masked, guardModels: false) else { return saved }
        return CodexConfig.parse(text, file: saved.file, exists: true)
    }

    private func detail(_ config: CodexConfig) -> String {
        switch config.permissionModel {
        case .both: return "sandbox_mode = \"\(config.sandboxMode ?? "")\" \u{00B7} default_permissions = \"\(config.defaultPermissions ?? "")\""
        case .profiles: return "default_permissions = \"\(config.defaultPermissions ?? "")\" \u{00B7} approval_policy = \"\(config.approvalPolicy ?? "on-request")\""
        case .legacy: return "sandbox_mode = \"\(config.sandboxMode ?? "read-only")\" \u{00B7} approval_policy = \"\(config.approvalPolicy ?? "on-request")\""
        }
    }

    private func choice(_ current: String, key: Key) -> Binding<String> {
        Binding(get: { current }, set: { value in
            switch key {
            case .approval:
                if value == (saved.approvalPolicy ?? "on-request") {
                    model.draft.remove { if case .codex(.approvalPolicy) = $0 { return true } else { return false } }
                } else {
                    model.draft.add(.change, "approval_policy \u{2192} \"\(value)\"", warning: value == "never" ? AgentsWording.neverWarning : nil, .codex(.approvalPolicy(value)))
                }
            case .sandbox:
                if value == (saved.sandboxMode ?? "read-only") {
                    model.draft.remove { if case .codex(.sandboxMode) = $0 { return true } else { return false } }
                } else {
                    model.draft.add(.change, "sandbox_mode \u{2192} \"\(value)\"", warning: value == "danger-full-access" ? AgentsWording.fullAccessWarning : nil,
                                    .codex(.sandboxMode(value)))
                }
            }
        })
    }

    @ViewBuilder
    private func legacy(_ shown: CodexConfig) -> some View {
        SettingRow(title: "Sandbox", key: "sandbox_mode", note: shown.sandboxMode == "danger-full-access" ? AgentsWording.fullAccessWarning : nil,
                   warn: shown.sandboxMode == "danger-full-access") {
            SegmentedControl(label: "Sandbox", options: AgentsWording.sandboxes.map { SegmentOption($0.title, value: $0.value, tone: $0.warn ? .warn : nil) },
                             selection: choice(shown.sandboxMode ?? "read-only", key: .sandbox))
        }
        if (shown.sandboxMode ?? "read-only") == "workspace-write" {
            Row { RowText("Network", subtitle: "sandbox_workspace_write.network_access", codeSubtitle: true) }
                .cells {
                    ReinsSwitch(label: "Network", isOn: Binding(get: { shown.networkAccess ?? false }, set: { on in
                        if on == (saved.networkAccess ?? false) {
                            model.draft.remove { if case .codex(.networkAccess) = $0 { return true } else { return false } }
                        } else {
                            model.draft.add(.change, "network_access \u{2192} \(on)", .codex(.networkAccess(on)))
                        }
                    }))
                }
            SectionRow("Writable roots", count: shown.writableRoots.count)
            ForEach(shown.writableRoots, id: \.self) { root in
                Row { RowText(root, mono: true) }
                    .lead { PageIcon(.folder, size: .row) }
                    .actions {
                        RowActionButton(title: "Remove \(root)", icon: .trash, iconOnly: true) {
                            model.draft.add(.remove, "writable root \(root)", .codex(.writableRoots(shown.writableRoots.filter { $0 != root })))
                        }
                    }
            }
            FormRow {
                HStack(spacing: Rhythm.tools) {
                    TextInputField(label: "New writable root", placeholder: "~/work/cache", text: $model.forms.root, code: true, focused: $rootFocused) { addRoot(shown) }
                    Button { addRoot(shown) } label: { ButtonLabel("Add", icon: .add) }
                        .buttonStyle(.reins(.normal))
                        .disabled(model.forms.root.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addRoot(_ shown: CodexConfig) {
        let root = model.forms.root.trimmingCharacters(in: .whitespaces)
        guard !root.isEmpty, !shown.writableRoots.contains(root) else { return }
        model.draft.add(.add, "writable root \(root)", .codex(.writableRoots(shown.writableRoots + [root])))
        model.forms.root = ""
    }
}

/// When both permission models are set: Codex reads only one, so the card offers to keep one (mock C′, `codex=both`).
struct BothModelsCard: View {
    @Bindable var model: AgentsModel
    let config: CodexConfig

    var body: some View {
        let kept = model.draft.items.compactMap { item -> CodexPermissionModel? in
            if case .codex(.keepModel(let kept)) = item.change { return kept } else { return nil }
        }.last
        GroupedList {
            CardHeader("Keep one permission model", detail: "Codex reads only one")
            FormRow {
                ChoiceCard(title: "Keep sandbox_mode", detail: "What Codex uses now. Removes default_permissions; the profiles stay in the file, unused.",
                           isOn: kept == .legacy) { keep(.legacy) }
                ChoiceCard(title: "Keep the profile \(config.defaultPermissions ?? "")", detail: "Removes sandbox_mode and [sandbox_workspace_write].",
                           isOn: kept == .profiles) { keep(.profiles) }
            }
        }
    }

    private func keep(_ choice: CodexPermissionModel) {
        let text = choice == .profiles ? "remove sandbox_mode and [sandbox_workspace_write]" : "remove default_permissions"
        model.draft.add(.change, text, .codex(.keepModel(choice)))
    }
}

/// Codex at a project: only the trust level; everything else comes from Global.
struct CodexTrustPanel: View {
    @Bindable var model: AgentsModel
    let config: CodexConfig
    let project: String

    var body: some View {
        let saved = config.trust[project] ?? ""
        let current: String = {
            for item in model.draft.items.reversed() { if case .codex(.trust(_, let level)) = item.change { return level ?? "" } }
            return saved
        }()
        GroupedList {
            CardHeader("Trust", detail: "projects.\"\((project as NSString).lastPathComponent)\".trust_level")
            SettingRow(title: "Trust this project", key: "trust_level", note: "Everything else comes from Global.") {
                SegmentedControl(label: "Trust", options: AgentsWording.trust.map { SegmentOption($0.title, value: $0.value) }, selection: Binding(get: { current }, set: { value in
                    if value == saved {
                        model.draft.remove { if case .codex(.trust) = $0 { return true } else { return false } }
                    } else {
                        model.draft.add(.change, "trust_level \u{2192} \(AgentsWording.title(value, in: AgentsWording.trust))", .codex(.trust(project: project, level: value.isEmpty ? nil : value)))
                    }
                }))
            }
        }
    }
}
