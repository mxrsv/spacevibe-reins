import ReinsCore
import SwiftUI

/// The `default_permissions` profile editor (spec, Interface: Permissions, Codex; mock C′ `codex=profiles`): the profile
/// picker with your profiles and the built-ins (described, never edited), and for a named profile its base, files and
/// network. Lives inside How Codex runs.
struct CodexProfileEditor: View {
    @Bindable var model: AgentsModel
    let config: CodexConfig
    @FocusState private var pathFocused: Bool
    @FocusState private var domainFocused: Bool

    var body: some View {
        let active = config.defaultPermissions ?? ""
        let builtin = AgentsWording.builtinProfiles.first { $0.value == active }
        SettingRow(title: "Permission profile", key: "default_permissions",
                   note: builtin.map { "\($0.detail) Built-in profiles cannot be changed; pick a named one to edit." }, warn: builtin?.warn ?? false) {
            MenuPicker(label: "Permission profile", options: profileOptions, selection: active, fill: true) { pick($0) }
        }
        if let profile = config.profile(active) {
            SectionRow("[permissions.\(profile.name)]")
            SettingRow(title: "Based on", key: "extends") {
                MenuPicker(label: "Based on", options: parents(profile).map { MenuOption(value: $0, title: $0, code: true) }, selection: profile.extends ?? "") { parent in
                    model.draft.add(.change, "\(profile.name) extends \u{2192} \"\(parent)\"", .codex(.profileExtends(profile: profile.name, parent: parent)))
                }
            }
            SectionRow("Files", count: profile.filesystem.count)
            FormRow {
                TextInputField(label: "Path or glob", placeholder: "~/path, or a glob like **/*.pem", text: $model.forms.path, code: true, focused: $pathFocused) { addPath(profile) }
                HStack(spacing: Rhythm.tools) {
                    SegmentedControl(label: "Access", options: access(AgentsWording.fileAccess), selection: $model.forms.pathAccess)
                    Spacer(minLength: 0)
                    Button { addPath(profile) } label: { ButtonLabel("Add", icon: .add) }.buttonStyle(.reins(.normal))
                        .disabled(model.forms.path.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            ForEach(profile.filesystem, id: \.path) { rule in
                Row { RowText(AgentsWording.pathLabel(rule.path), subtitle: "filesystem.\"\(rule.path)\"", codeSubtitle: true) }
                    .cells {
                        SegmentedControl(label: "Access for \(rule.path)", options: access(AgentsWording.fileAccess), selection: Binding(get: { rule.access }, set: { value in
                            model.draft.add(.change, "\(profile.name): \(AgentsWording.pathLabel(rule.path)) \u{2192} \(value)", tag: value.capitalized,
                                            tone: AgentsTone.access(value), .codex(.pathRule(profile: profile.name, path: rule.path, access: value)))
                        }))
                    }
                    .actions {
                        RowActionButton(title: "Remove \(rule.path)", icon: .trash, iconOnly: true) {
                            model.draft.add(.remove, "\(profile.name): \(AgentsWording.pathLabel(rule.path))", .codex(.pathRule(profile: profile.name, path: rule.path, access: nil)))
                        }
                    }
            }
            if profile.filesystem.isEmpty { EmptyRow("Only what the base profile allows.") }
            network(profile)
        }
    }

    private var profileOptions: [MenuOption<String>] {
        var out = config.profiles.enumerated().map { index, profile in
            MenuOption(value: profile.name, title: profile.name, section: index == 0 ? "Your profiles" : nil, code: true)
        }
        for (index, builtin) in AgentsWording.builtinProfiles.enumerated() {
            out.append(MenuOption(value: builtin.value, title: builtin.title, detail: builtin.detail, warn: builtin.warn, section: index == 0 ? "Built in" : nil, code: true))
        }
        return out
    }

    private func parents(_ profile: CodexPermissionProfile) -> [String] {
        [":read-only", ":workspace"] + config.profiles.map(\.name).filter { $0 != profile.name }
    }

    private func access(_ list: [AgentChoice]) -> [SegmentOption<String>] {
        list.map { SegmentOption($0.title, value: $0.value, tone: AgentsTone.segment($0.value)) }
    }

    private func pick(_ name: String) {
        let warning = name == ":danger-full-access" ? AgentsWording.fullAccessWarning : nil
        model.draft.add(.change, "default_permissions \u{2192} \"\(name)\"", warning: warning, .codex(.defaultPermissions(name)))
    }

    private func addPath(_ profile: CodexPermissionProfile) {
        let raw = model.forms.path.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        // A bare glob is relative to the workspace roots, as in the mock.
        let path = raw.hasPrefix("~") || raw.hasPrefix("/") || raw.hasPrefix(":") ? raw : ":workspace_roots/\(raw)"
        let access = model.forms.pathAccess
        model.draft.add(.add, "\(profile.name): \(AgentsWording.pathLabel(path))", tag: access.capitalized, tone: AgentsTone.access(access),
                        .codex(.pathRule(profile: profile.name, path: path, access: access)))
        model.forms.path = ""
    }

    @ViewBuilder
    private func network(_ profile: CodexPermissionProfile) -> some View {
        SectionRow("Network")
        Row { RowText("Network", subtitle: "network.enabled", codeSubtitle: true) }
            .cells {
                ReinsSwitch(label: "Network", isOn: Binding(get: { profile.networkEnabled }, set: { on in
                    model.draft.add(.change, "\(profile.name) network.enabled \u{2192} \(on)", .codex(.networkEnabled(profile: profile.name, on)))
                }))
            }
        if profile.networkEnabled {
            Row { RowText("Enforce domain rules", subtitle: "features.network_proxy", codeSubtitle: true) }
                .cells {
                    ReinsSwitch(label: "Enforce domain rules", isOn: Binding(get: { config.networkProxy }, set: { on in
                        model.draft.add(.change, "features.network_proxy \u{2192} \(on)", warning: on ? nil : AgentsWording.openNetworkWarning, .codex(.networkProxy(on)))
                    }))
                }
            if !config.networkProxy { WarningNote(text: "Without it, the network is open to every domain.").padding(.horizontal, Metrics.rowHorizontalPadding) }
            FormRow {
                TextInputField(label: "Host", placeholder: "Host, *.example.com or **.example.com", text: $model.forms.domain, code: true, focused: $domainFocused) { addDomain(profile) }
                HStack(spacing: Rhythm.tools) {
                    SegmentedControl(label: "Domain access", options: access(AgentsWording.domainAccess), selection: $model.forms.domainAccess)
                    Spacer(minLength: 0)
                    Button { addDomain(profile) } label: { ButtonLabel("Add", icon: .add) }.buttonStyle(.reins(.normal))
                        .disabled(model.forms.domain.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            ForEach(profile.domains, id: \.host) { domain in
                Row { RowText(domain.host, mono: true) }
                    .cells { Tag(domain.access.capitalized, tone: AgentsTone.access(domain.access)) }
                    .actions {
                        RowActionButton(title: "Remove \(domain.host)", icon: .trash, iconOnly: true) {
                            model.draft.add(.remove, "\(profile.name): \(domain.host)", .codex(.domain(profile: profile.name, host: domain.host, access: nil)))
                        }
                    }
            }
            if profile.domains.isEmpty { EmptyRow("No domain rules: every external destination is blocked.") }
        }
    }

    private func addDomain(_ profile: CodexPermissionProfile) {
        let host = model.forms.domain.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        let access = model.forms.domainAccess
        model.draft.add(.add, "\(profile.name): \(host)", tag: access.capitalized, tone: AgentsTone.access(access),
                        .codex(.domain(profile: profile.name, host: host, access: access)))
        model.forms.domain = ""
    }
}

/// Codex's command rules: each `prefix_rule` with its decision tag menu, an add row and remove. A file Reins cannot read
/// as `prefix_rule` calls shows the reason and stays read-only.
struct CodexCommandRules: View {
    @Bindable var model: AgentsModel
    let rules: [CodexRulesFile]
    @FocusState private var focused: Bool

    var body: some View {
        GroupedList {
            CardHeader("Command rules", count: rules.map(\.rules.count).reduce(0, +), detail: "rules/*.rules")
            if let writable = rules.first(where: { $0.readOnlyReason == nil }) {
                FormRow {
                    TextInputField(label: "Command prefix", placeholder: "git push", text: $model.forms.commandRule, code: true, focused: $focused) { add(writable) }
                    HStack(spacing: Rhythm.tools) {
                        SegmentedControl(label: "Decision", options: AgentsWording.decisions.map { SegmentOption($0.title, value: $0.value, tone: AgentsTone.segment($0.value)) },
                                         selection: $model.forms.decision)
                        Spacer(minLength: 0)
                        Button { add(writable) } label: { ButtonLabel("Add", icon: .add) }.buttonStyle(.reins(.normal))
                            .disabled(model.forms.commandRule.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            ForEach(rules, id: \.file) { file in
                if let reason = file.readOnlyReason {
                    Row { RowText(file.file.lastPathComponent, subtitle: reason) { Tag("Read only", icon: .lock) } }
                }
                ForEach(file.rules) { rule in row(rule, in: file) }
            }
            if rules.allSatisfy({ $0.rules.isEmpty }) { EmptyRow("No command rules.") }
        }
    }

    private func row(_ rule: CodexCommandRule, in file: CodexRulesFile) -> some View {
        let removed = model.draft.rules(for: file.file).contains(.remove(pattern: rule.pattern))
        let decision = model.draft.rules(for: file.file).reversed().compactMap { change -> String? in
            if case .decision(let pattern, let to) = change, pattern == rule.pattern { return to } else { return nil }
        }.first ?? rule.decision
        let title = AgentsWording.title(decision, in: AgentsWording.decisions)
        return Row { RowText(rule.text, mono: true) { if removed { Tag("removed", tone: .danger) } } }
            .cells {
                if file.readOnlyReason == nil {
                    TagMenu(title: title, tone: AgentsTone.access(decision), moves: AgentsWording.decisions.filter { $0.value != decision }.map { target in
                        (title: target.title, action: {
                            model.draft.add(.change, "\(rule.text): \(title) \u{2192} \(target.title)", tag: target.title, tone: AgentsTone.access(target.value),
                                            .codexRule(file: file.file, .decision(pattern: rule.pattern, to: target.value)))
                        })
                    }, remove: { remove(rule, file) })
                } else {
                    Tag(title, tone: AgentsTone.access(decision))
                }
            }
            .actions {
                if file.readOnlyReason == nil {
                    RowActionButton(title: "Remove \(rule.text)", icon: .trash, iconOnly: true) { remove(rule, file) }
                }
            }
    }

    private func remove(_ rule: CodexCommandRule, _ file: CodexRulesFile) {
        model.draft.add(.remove, rule.text, tag: AgentsWording.title(rule.decision, in: AgentsWording.decisions), tone: AgentsTone.access(rule.decision),
                        .codexRule(file: file.file, .remove(pattern: rule.pattern)))
    }

    private func add(_ file: CodexRulesFile) {
        let words = model.forms.commandRule.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return }
        let decision = model.forms.decision
        model.draft.add(.add, words.joined(separator: " "), tag: AgentsWording.title(decision, in: AgentsWording.decisions), tone: AgentsTone.access(decision),
                        .codexRule(file: file.file, .add(pattern: words, decision: decision)))
        model.forms.commandRule = ""
    }
}
