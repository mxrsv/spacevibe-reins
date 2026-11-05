import Foundation
import ReinsCore

/// What the two agent cards show, always at Global (spec, Interface: Page).
struct AgentsOverview {
    var projects: [String]
    var claude: ClaudeSettings
    var claudeMCP: Int
    var codex: CodexConfig
    /// Every hook of both CLIs and every scope; runs are attached once the usage scan is done.
    var inventory: InventorySnapshot

    func hooks(_ agent: AgentKind, file: String? = nil) -> [InventoryHook] {
        inventory.hooks.filter { $0.cli == agent.cli && (file == nil || $0.file == file) }
    }
}

/// The model panel's data: the value at the scope, the one at Global, Codex's effort, and the models seen in the logs.
struct ModelData: Equatable {
    var current: String?
    var global: String?
    var effort: String?
    var seen: [ModelCount]
}

/// What one open panel shows for its agent and scope, read off the main thread. Secrets never enter it: settings files
/// arrive parsed (names only) or masked.
enum PanelData {
    case instructions(InstructionFile)
    case claudePermissions(ClaudeSettings, global: ClaudeSettings)
    case codexPermissions(CodexConfig, masked: String, rules: [CodexRulesFile])
    case codexTrust(CodexConfig, project: String)
    case hooks([InventoryHook], file: URL)
    case mcp([MCPServer], plugins: [MCPServer], problem: String?)
    case model(ModelData)
    case advanced(MaskedText, file: URL)
    case unavailable(String)
}

/// The reads of the Agents page. Every function reads the disk synchronously: call it off the main thread.
enum AgentsReader {
    static func overview(_ roots: Roots) -> AgentsOverview {
        let projects = Inventory.discoverProjects(roots: roots)
        return AgentsOverview(
            projects: projects,
            claude: ClaudeSettingsEdit.read(roots.claude.hookFile),
            claudeMCP: ClaudeStateMCP.read(roots, project: nil).servers.count + MCPFile.pluginServers(roots).count,
            codex: CodexConfig.read(AgentsSavePlan.codexConfigFile(roots)),
            inventory: Inventory.read(roots: roots)
        )
    }

    /// The scopes a panel offers (spec, Interface: Scope): Claude Code has Global, then each project and its Local file;
    /// Codex has projects only for Rules and Permissions (the trust level).
    static func scopes(_ agent: AgentKind, _ panel: AgentPanel, projects: [String]) -> [RuleScope] {
        switch agent {
        case .claude: return [.global] + projects.flatMap { [RuleScope.project($0), .local($0)] }
        case .codex: return panel == .rules || panel == .permissions ? [.global] + projects.map { RuleScope.project($0) } : [.global]
        }
    }

    static func panel(_ roots: Roots, _ agent: AgentKind, _ panel: AgentPanel, _ scope: RuleScope, overview: AgentsOverview, home: String) -> PanelData {
        let context = AgentsSavePlan.Context(roots: roots, projects: overview.projects, agent: agent, panel: panel, scope: scope)
        do {
            switch (agent, panel) {
            case (_, .rules):
                guard let url = InstructionFile.url(cli: agent.cli, scope: scope, roots: roots) else { return .unavailable("Codex has no Local instruction file.") }
                return .instructions(InstructionFile.read(url, home: home))
            case (.claude, .permissions):
                return .claudePermissions(ClaudeSettingsEdit.read(try AgentsSavePlan.settingsFile(context)), global: overview.claude)
            case (.codex, .permissions):
                if case .project(let dir) = scope { return .codexTrust(overview.codex, project: dir) }
                let file = AgentsSavePlan.codexConfigFile(roots)
                return .codexPermissions(CodexConfig.read(file), masked: SecretMask.maskTOMLFile(file).text, rules: CodexRulesFile.readAll(roots))
            case (.claude, .hooks):
                let file = try AgentsSavePlan.settingsFile(context)
                let plugins = scope == .global ? overview.inventory.hooks.filter { $0.cli == .claude && !$0.removable } : []
                return .hooks(overview.hooks(.claude, file: file.path) + plugins, file: file)
            case (.codex, .hooks):
                return .hooks(overview.hooks(.codex), file: roots.codex.hookFile)
            case (.claude, .mcp):
                switch scope {
                case .global:
                    let read = ClaudeStateMCP.read(roots, project: nil)
                    return .mcp(read.servers, plugins: MCPFile.pluginServers(roots), problem: read.problem)
                case .local(let dir):
                    let read = ClaudeStateMCP.read(roots, project: dir)
                    return .mcp(read.servers, plugins: [], problem: read.problem)
                case .project(let dir):
                    let read = MCPFile.read(project: dir)
                    return .mcp(read.servers, plugins: [], problem: read.problem)
                }
            case (.codex, .mcp):
                return .mcp(overview.codex.mcpServers, plugins: [], problem: nil)
            case (.claude, .model):
                let settings = ClaudeSettingsEdit.read(try AgentsSavePlan.settingsFile(context))
                return .model(ModelData(current: settings.model, global: overview.claude.model, effort: nil, seen: ModelUsage.seen(roots, cli: .claude)))
            case (.codex, .model):
                return .model(ModelData(current: overview.codex.model, global: nil, effort: overview.codex.reasoningEffort, seen: ModelUsage.seen(roots, cli: .codex)))
            case (_, .advanced):
                let file = agent == .claude ? try AgentsSavePlan.settingsFile(context) : AgentsSavePlan.codexConfigFile(roots)
                if agent == .codex { return .advanced(SecretMask.maskTOMLFile(file), file: file) }
                do { return .advanced(try SecretMask.maskJSONFile(file), file: file) } catch {
                    return .unavailable("\(AgentsPaths.display(file, roots: roots)) is not valid JSON, so it cannot open here without showing what it holds. Fix it in a text editor first.")
                }
            }
        } catch {
            // The engine's sentence, never a raw description (S-R3).
            return .unavailable((error as? ReinsError)?.message ?? "This panel could not be read.")
        }
    }
}
