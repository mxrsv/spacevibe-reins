import ReinsCore
import SwiftUI

/// Permissions for Claude Code (spec, Interface: Permissions, Claude Code): the default mode with its description, the rules
/// card (an add row, then Allow, Ask and Deny groups, each hidden while empty) and the extra folders. Everything shown is
/// the saved file with the draft applied.
struct ClaudePermissionsPanel: View {
    @Bindable var model: AgentsModel
    let saved: ClaudeSettings
    let global: ClaudeSettings
    @FocusState private var ruleFocused: Bool
    @FocusState private var folderFocused: Bool

    var body: some View {
        let shown = saved.applying(model.draft.claudeChanges)
        if let problem = saved.problem { Banner(.error, message: "This settings file cannot be edited here", detail: problem) }
        GroupedList {
            CardHeader("Default mode", detail: "permissions.defaultMode")
            SettingRow(title: "Mode", key: nil, note: modeNote(shown), warn: shown.defaultMode == "bypassPermissions") {
                MenuPicker(label: "Default mode", options: modeOptions, selection: shown.defaultMode ?? "", fill: true) { pick(mode: $0) }
            }
        }
        GroupedList {
            CardHeader("Rules", count: shown.allow.count + shown.ask.count + shown.deny.count)
            FormRow {
                TextInputField(label: "New rule", placeholder: "Bash(npm test *)", text: $model.forms.rule, code: true,
                               invalid: model.forms.ruleError != nil, focused: $ruleFocused) { addRule(shown) }
                HStack(spacing: Rhythm.tools) {
                    SegmentedControl(label: "Verdict for the new rule", options: RulesWording.verdicts.map {
                        SegmentOption(RulesWording.title($0), value: $0, tone: RulesWording.segmentTone($0))
                    }, selection: $model.forms.verdict)
                    Spacer(minLength: 0)
                    Button { addRule(shown) } label: { ButtonLabel("Add", icon: .add) }
                        .buttonStyle(.reins(.normal))
                        .disabled(model.forms.rule.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error = model.forms.ruleError { Text(error).reinsText(.caption, tone: .danger) }
            }
            ForEach(RulesWording.listOrder, id: \.self) { verdict in
                let rules = shown.rules(verdict)
                if !rules.isEmpty {
                    SectionRow(RulesWording.groupTitle(verdict), count: rules.count)
                    ForEach(rules, id: \.self) { rule in ruleRow(rule, verdict: verdict) }
                }
            }
            if shown.allow.isEmpty && shown.ask.isEmpty && shown.deny.isEmpty { EmptyRow("No rules in this file.") }
        }
        GroupedList {
            CardHeader("Extra folders", count: shown.additionalDirectories.count, detail: "additionalDirectories")
            ForEach(shown.additionalDirectories, id: \.self) { folder in
                Row { RowText(folder, mono: true) }
                    .lead { PageIcon(.folder, size: .row) }
                    .actions {
                        RowActionButton(title: "Remove \(folder)", icon: .trash, iconOnly: true) {
                            model.draft.add(.remove, folder, .claude(.removeDirectory(folder)))
                        }
                    }
            }
            FormRow {
                HStack(spacing: Rhythm.tools) {
                    TextInputField(label: "New folder", placeholder: "~/work/shared", text: $model.forms.folder, code: true, focused: $folderFocused) { addFolder() }
                    Button { addFolder() } label: { ButtonLabel("Add", icon: .add) }
                        .buttonStyle(.reins(.normal))
                        .disabled(model.forms.folder.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var modeOptions: [MenuOption<String>] {
        var out = AgentsWording.modes.map { MenuOption(value: $0.value, title: $0.title, detail: $0.detail, warn: $0.warn) }
        if model.currentScope != .global {
            let inherited = AgentsWording.title(global.defaultMode ?? "default", in: AgentsWording.modes)
            out.insert(MenuOption(value: "", title: "Same as Global (\(inherited))"), at: 0)
        }
        return out
    }

    private func modeNote(_ shown: ClaudeSettings) -> String {
        guard let mode = shown.defaultMode else {
            return "Uses Global: \(AgentsWording.title(global.defaultMode ?? "default", in: AgentsWording.modes))."
        }
        return AgentsWording.modes.first { $0.value == mode }?.detail ?? mode
    }

    private func pick(mode: String) {
        let next: String? = mode.isEmpty ? nil : mode
        if next == saved.defaultMode {
            model.draft.remove { if case .claude(.defaultMode) = $0 { return true } else { return false } }
            return
        }
        let title = next.map { AgentsWording.title($0, in: AgentsWording.modes) } ?? "Same as Global"
        model.draft.add(.change, "defaultMode \u{2192} \(title)", warning: next == "bypassPermissions" ? AgentsWording.bypassWarning : nil,
                        .claude(.defaultMode(next)))
    }

    private func addRule(_ shown: ClaudeSettings) {
        do {
            let rule = try ClaudeSettingsEdit.checkNewRule(model.forms.rule, in: shown)
            let verdict = model.forms.verdict
            model.draft.add(.add, rule, tag: RulesWording.title(verdict), tone: AgentsTone.verdict(verdict), .claude(.addRule(verdict, rule)))
            model.forms.rule = ""
            model.forms.ruleError = nil
        } catch {
            model.forms.ruleError = AppEnvironment.message(error)
        }
    }

    private func addFolder() {
        let folder = model.forms.folder.trimmingCharacters(in: .whitespaces)
        guard !folder.isEmpty else { return }
        model.draft.add(.add, folder, .claude(.addDirectory(folder)))
        model.forms.folder = ""
    }

    private func ruleRow(_ rule: String, verdict: RuleVerdict) -> some View {
        Row { RowText(rule, mono: true) }
            .cells {
                TagMenu(title: RulesWording.title(verdict), tone: AgentsTone.verdict(verdict), moves: RulesWording.verdicts.filter { $0 != verdict }.map { target in
                    (title: RulesWording.title(target), action: {
                        model.draft.add(.change, "\(rule): \(RulesWording.title(verdict)) \u{2192} \(RulesWording.title(target))", tag: RulesWording.title(target),
                                        tone: AgentsTone.verdict(target), .claude(.moveRule(rule, from: verdict, to: target)))
                    })
                }, remove: { removeRule(rule, verdict) })
            }
            .actions {
                RowActionButton(title: "Remove \(rule)", icon: .trash, iconOnly: true) { removeRule(rule, verdict) }
            }
    }

    private func removeRule(_ rule: String, _ verdict: RuleVerdict) {
        model.draft.add(.remove, rule, tag: RulesWording.title(verdict), tone: AgentsTone.verdict(verdict), .claude(.removeRule(verdict, rule)))
    }
}

/// The tag tones the Agents page gives verdicts and access levels: allowing reads as success, asking as warn, denying as
/// danger.
enum AgentsTone {
    static func verdict(_ verdict: RuleVerdict) -> TagTone {
        switch verdict {
        case .allow: .success
        case .ask: .warn
        case .deny: .danger
        }
    }

    static func access(_ value: String) -> TagTone {
        switch value {
        case "allow", "read": .success
        case "prompt", "write": .warn
        case "deny", "forbidden": .danger
        default: .neutral
        }
    }

    static func segment(_ value: String) -> SegmentTone? {
        switch access(value) {
        case .success: .success
        case .warn: .warn
        case .danger: .danger
        default: nil
        }
    }
}
