import AppKit
import ReinsCore
import SwiftUI

/// The open panel: the inspector frame with its header, its tools row (the panel's scope picker, the file and Show in
/// Finder; Edit | Preview and Open in editor in Rules) and the body for the panel and CLI.
struct AgentsPanelHost: View {
    @Bindable var model: AgentsModel
    let open: OpenPanel

    var body: some View {
        InspectorPanel(
            cli: open.agent.cli, title: open.panel.title, agent: open.agent.name,
            width: open.panel == .advanced ? $model.advancedWidth : $model.panelWidth,
            draftCount: model.draft.count, asksToDiscard: model.leaving != nil,
            close: { model.close() }, discard: { model.discard() }, keepEditing: { model.keepEditing() }, review: { model.review() }
        ) {
            tools
        } content: {
            content
        }
    }

    private var file: URL? {
        switch model.data {
        case .instructions(let file): return (model.shownImport ?? file).file
        case .claudePermissions(let settings, _): return settings.file
        case .codexPermissions(let config, _, _), .codexTrust(let config, _): return config.file
        case .hooks(_, let file): return file
        case .advanced(_, let file): return file
        default: return nil
        }
    }

    private var tools: some View {
        let scopes = model.scopeOptions(for: open)
        let current = model.currentScope
        return HStack(spacing: Rhythm.tools) {
            if scopes.count > 1 {
                ScopePicker(
                    options: scopes.map { ScopeOption(id: AgentsPanelHost.key($0), label: AgentsWording.scopeTitle($0)) },
                    current: ScopeOption(id: AgentsPanelHost.key(current), label: AgentsWording.scopeTitle(current)),
                    minWidth: Metrics.scopePickerMinWidth
                ) { picked in
                    if let scope = scopes.first(where: { AgentsPanelHost.key($0) == picked.id }) { model.select(scope: scope) }
                }
            }
            if open.panel == .rules {
                SegmentedControl(label: "Rules view", options: [
                    SegmentOption("Edit", value: true), SegmentOption("Preview", value: false),
                ], selection: $model.isEditing)
            }
            if let file {
                Text(model.env.roots.map { AgentsPaths.display(file, roots: $0) } ?? file.path)
                    .reinsText(.code, tone: .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if open.panel == .rules {
                    Button { _ = NSWorkspace.shared.open(file) } label: { PageIcon(.external) }
                        .buttonStyle(.reins(.icon)).help("Open in editor").accessibilityLabel("Open in editor")
                } else {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: { PageIcon(.folder) }
                        .buttonStyle(.reins(.icon)).help("Show in Finder").accessibilityLabel("Show in Finder")
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    static func key(_ scope: RuleScope) -> String? {
        switch scope {
        case .global: nil
        case .project(let dir): "project:\(dir)"
        case .local(let dir): "local:\(dir)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.data {
        case nil:
            EmptyState("Reading\u{2026}", icon: .refresh)
        case .unavailable(let reason)?:
            EmptyState("This panel cannot open here", message: reason, icon: .warning)
        case .instructions(let file)?:
            InstructionsPanel(model: model, base: file)
        case .claudePermissions(let settings, let global)?:
            ClaudePermissionsPanel(model: model, saved: settings, global: global)
        case .codexPermissions(let config, let masked, let rules)?:
            CodexPermissionsPanel(model: model, saved: config, masked: masked, rules: rules)
        case .codexTrust(let config, let project)?:
            CodexTrustPanel(model: model, config: config, project: project)
        case .hooks(let hooks, _)?:
            HooksPanel(model: model, agent: open.agent, hooks: hooks)
        case .mcp(let servers, let plugins, let problem)?:
            MCPPanel(model: model, agent: open.agent, saved: servers, plugins: plugins, problem: problem)
        case .model(let data)?:
            ModelPanel(model: model, agent: open.agent, data: data)
        case .advanced(let masked, _)?:
            AdvancedPanel(model: model, masked: masked)
        }
    }
}
