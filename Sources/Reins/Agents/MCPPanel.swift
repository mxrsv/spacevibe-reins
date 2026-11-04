import ReinsCore
import SwiftUI

/// MCP (spec, Interface: MCP): each server's name, kind and target; a plugin's server is read-only with a lock tag; a row
/// expands to its secrets, names only, every value hidden and each one replaceable. Add server and remove.
struct MCPPanel: View {
    @Bindable var model: AgentsModel
    let agent: AgentKind
    let saved: [MCPServer]
    let plugins: [MCPServer]
    let problem: String?
    @FocusState private var nameFocused: Bool
    @FocusState private var targetFocused: Bool
    @FocusState private var secretFocused: Bool

    var body: some View {
        let removed = removedNames
        let shown = saved.filter { !removed.contains($0.name) } + addedServers + plugins
        if let problem { Banner(.warn, message: "Some servers cannot be shown", detail: problem) }
        GroupedList {
            CardHeader("Servers", count: shown.count)
            ForEach(shown) { server in
                row(server)
                if model.forms.expandedServers.contains(server.name) {
                    ForEach(server.secretNames, id: \.self) { secret in secretRow(server, secret) }
                    if server.secretNames.isEmpty { EmptyRow("No environment or headers.") }
                }
            }
            if shown.isEmpty { EmptyRow("No MCP servers here.") }
        }
        GroupedList {
            CardHeader("Add server")
            FormRow {
                HStack(spacing: Rhythm.tools) {
                    TextInputField(label: "Server name", placeholder: "docs", text: $model.forms.serverName, code: true, focused: $nameFocused) {}
                    SegmentedControl(label: "Kind", options: [SegmentOption("Command", value: MCPServer.Kind.command), SegmentOption("URL", value: MCPServer.Kind.url)],
                                     selection: $model.forms.serverKind)
                }
                HStack(spacing: Rhythm.tools) {
                    TextInputField(label: "Target", placeholder: model.forms.serverKind == .url ? "https://mcp.example.com/mcp" : "npx -y @scope/server",
                                   text: $model.forms.serverTarget, code: true, focused: $targetFocused) { add() }
                    Button { add() } label: { ButtonLabel("Add server", icon: .add) }
                        .buttonStyle(.reins(.normal))
                        .disabled(model.forms.serverName.trimmingCharacters(in: .whitespaces).isEmpty || model.forms.serverTarget.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var addedServers: [MCPServer] {
        model.draft.items.compactMap { item in
            switch item.change {
            case .mcp(.add(let name, let kind, let target)), .codex(.addServer(let name, let kind, let target)):
                return MCPServer(name: name, kind: kind, target: target, secretNames: [], plugin: nil)
            default:
                return nil
            }
        }
    }

    private var removedNames: Set<String> {
        Set(model.draft.items.compactMap { item in
            switch item.change {
            case .mcp(.remove(let name)), .codex(.removeServer(let name)): return name
            default: return nil
            }
        })
    }

    private func row(_ server: MCPServer) -> some View {
        let expanded = model.forms.expandedServers.contains(server.name)
        return Row(onActivate: { toggle(server) }) {
            RowText(server.name, subtitle: server.target, codeSubtitle: true) {
                Tag(server.kind == .url ? "URL" : "command")
                if let plugin = server.plugin { Tag("plugin: \(plugin)", icon: .lock) }
                if !server.secretNames.isEmpty { Tag(AgentsWording.plural(server.secretNames.count, "secret"), icon: .key) }
            }
        }
        .lead { Chevron(expanded ? .down : .right, size: .row) }
        .actions {
            if server.plugin == nil {
                RowActionButton(title: "Remove \(server.name)", icon: .trash, kind: .danger, iconOnly: true) {
                    let change: DraftChange = agent == .claude ? .mcp(.remove(name: server.name)) : .codex(.removeServer(name: server.name))
                    model.draft.add(.remove, server.name, tone: .danger, change)
                }
            }
        }
    }

    private func toggle(_ server: MCPServer) {
        if model.forms.expandedServers.contains(server.name) { model.forms.expandedServers.remove(server.name) } else { model.forms.expandedServers.insert(server.name) }
    }

    @ViewBuilder
    private func secretRow(_ server: MCPServer, _ secret: MCPSecretName) -> some View {
        let replacing = model.forms.replacing.map { $0.server == server.name && $0.secret == secret } ?? false
        Row {
            RowText(secret.name, subtitle: secret.table, mono: true) {
                Text(replaced(server, secret) ? "new value" : SecretMask.placeholder).reinsText(.code, tone: .tertiary)
            }
        }
        .lead { PageIcon(.key, size: .row) }
        .actions {
            if server.plugin == nil {
                RowActionButton(title: "Replace", icon: .edit) { model.forms.replacing = (server.name, secret); model.forms.secretValue = "" }
            }
        }
        .groupedListPart(.detail)
        if replacing {
            FormRow {
                HStack(spacing: Rhythm.tools) {
                    TextInputField(label: "New value for \(secret.name)", placeholder: "New value", text: $model.forms.secretValue, code: true, focused: $secretFocused) {
                        replace(server, secret)
                    }
                    Button("Cancel") { model.forms.replacing = nil }.buttonStyle(.reins(.ghost))
                    Button { replace(server, secret) } label: { ButtonLabel("Replace", icon: .check) }
                        .buttonStyle(.reins(.normal))
                        .disabled(model.forms.secretValue.isEmpty)
                }
                Text("The old value never leaves the file; the new one is written in its place.").reinsText(.caption, tone: .tertiary)
            }
        }
    }

    private func replaced(_ server: MCPServer, _ secret: MCPSecretName) -> Bool {
        model.draft.items.contains { item in
            switch item.change {
            case .mcp(.replaceSecret(let s, let table, let name, _)), .codex(.replaceSecret(let s, let table, let name, _)):
                return s == server.name && table == secret.table && name == secret.name
            default:
                return false
            }
        }
    }

    private func replace(_ server: MCPServer, _ secret: MCPSecretName) {
        let value = model.forms.secretValue
        guard !value.isEmpty else { return }
        let change: DraftChange = agent == .claude
            ? .mcp(.replaceSecret(server: server.name, table: secret.table, name: secret.name, value: value))
            : .codex(.replaceSecret(server: server.name, table: secret.table, name: secret.name, value: value))
        model.draft.add(.replace, "\(secret.name) in \(server.name)", change)
        model.forms.replacing = nil
        model.forms.secretValue = ""
    }

    private func add() {
        let name = model.forms.serverName.trimmingCharacters(in: .whitespaces)
        let target = model.forms.serverTarget.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !target.isEmpty else { return }
        let kind = model.forms.serverKind
        let change: DraftChange = agent == .claude ? .mcp(.add(name: name, kind: kind, target: target)) : .codex(.addServer(name: name, kind: kind, target: target))
        model.draft.add(.add, "\(name) (\(target))", change)
        model.forms.serverName = ""
        model.forms.serverTarget = ""
    }
}
