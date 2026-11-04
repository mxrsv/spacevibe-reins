import ReinsCore
import SwiftUI

/// The `Claude Code | Codex` switch (⌥⌘1, ⌥⌘2), the scope picker (Global or a discovered project) and what the scope means
/// for the CLI on screen: for Claude Code the Shared / Local switch and the settings file, for Codex its one config file
/// and a button that shows it in the Finder.
struct RulesToolbar: View {
    let model: RulesModel
    let snapshot: RulesSnapshot

    static func scopeOptions(projects: [RulesProject]) -> [ScopeOption] {
        [ScopeOption(id: nil, label: "Global")] + projects.map { ScopeOption(id: $0.dir, label: $0.name) }
    }

    /// A selected project that is no longer discovered still shows as "Project".
    static func currentScope(options: [ScopeOption], dir: String?) -> ScopeOption {
        options.first { $0.id == dir } ?? ScopeOption(id: dir, label: "Project")
    }

    static var cliOptions: [SegmentOption<InventoryCLI>] { [
        SegmentOption(InventoryCLI.claude.label, value: InventoryCLI.claude, cli: .claude, shortcut: KeyboardShortcut("1", modifiers: [.command, .option])),
        SegmentOption(InventoryCLI.codex.label, value: InventoryCLI.codex, cli: .codex, shortcut: KeyboardShortcut("2", modifiers: [.command, .option])),
    ] }

    var body: some View {
        let options = Self.scopeOptions(projects: snapshot.projects)
        HStack(spacing: Rhythm.tools) {
            SegmentedControl(label: "Rules for", options: Self.cliOptions, selection: Binding(get: { model.cli }, set: { model.selectCLI($0) }))
            ScopePicker(
                options: options, current: Self.currentScope(options: options, dir: snapshot.selection.dir),
                minWidth: Metrics.scopePickerMinWidth, onSelect: { model.selectProject($0.id) }
            )
            if model.cli == .claude, snapshot.selection.dir != nil {
                SegmentedControl(
                    label: "Settings file",
                    options: [SegmentOption("Shared", value: RulesFileKind.shared), SegmentOption("Local", value: RulesFileKind.local)],
                    selection: Binding(get: { snapshot.selection.file }, set: { model.selectFile($0) })
                )
            }
            HStack(spacing: Space.s6) {
                Text(model.cli == .claude ? snapshot.fileLabel : "~/.codex/config.toml").reinsText(.code, tone: .tertiary)
                Text("\u{00B7}")
                Text(scopeMeaning)
            }
            .reinsText(.caption, tone: .tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, Space.s8)
            Spacer(minLength: 0)
            if model.cli == .codex {
                Button("Show in Finder") { model.revealCodexConfig() }
                    .buttonStyle(.reins(.normal))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopeMeaning: String {
        switch (model.cli, snapshot.selection.dir) {
        case (.claude, nil): "Applies to every project"
        case (.claude, _): "Adds to Global rules"
        case (.codex, nil): "Applies to every project"
        case (.codex, _): "Only the trust level is per project"
        }
    }
}
