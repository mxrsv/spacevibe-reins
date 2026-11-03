import SwiftUI

/// The scope picker (Global or a discovered project), the Shared / Local switch for a project, and the file the scope means.
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

    var body: some View {
        let options = Self.scopeOptions(projects: snapshot.projects)
        HStack(spacing: Rhythm.tools) {
            ScopePicker(
                options: options, current: Self.currentScope(options: options, dir: snapshot.selection.dir),
                minWidth: Metrics.scopePickerMinWidth, onSelect: { model.selectProject($0.id) }
            )
            if snapshot.selection.dir != nil {
                SegmentedControl(
                    label: "Settings file",
                    options: [SegmentOption("Shared", value: RulesFileKind.shared), SegmentOption("Local", value: RulesFileKind.local)],
                    selection: Binding(get: { snapshot.selection.file }, set: { model.selectFile($0) })
                )
            }
            HStack(spacing: Space.s6) {
                Text(snapshot.fileLabel).reinsText(.code, tone: .tertiary)
                Text("\u{00B7}")
                Text(snapshot.selection.dir == nil ? "Applies to every project" : "Adds to Global rules")
            }
            .reinsText(.caption, tone: .tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, Space.s8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
