import SwiftUI

/// The scope picker (Global or a discovered project), the Shared / Local switch for a project, and the file the scope means.
struct RulesToolbar: View {
    let model: RulesModel
    let snapshot: RulesSnapshot

    private var scopeOptions: [ScopeOption] {
        [ScopeOption(id: nil, label: "Global")] + snapshot.projects.map { ScopeOption(id: $0.dir, label: $0.name) }
    }

    /// A selected project that is no longer discovered still shows as "Project".
    private var currentScope: ScopeOption {
        scopeOptions.first { $0.id == snapshot.selection.dir } ?? ScopeOption(id: snapshot.selection.dir, label: "Project")
    }

    var body: some View {
        HStack(spacing: 10) {
            ScopePicker(options: scopeOptions, current: currentScope, minWidth: 130, onSelect: { model.selectProject($0.id) })
            if snapshot.selection.dir != nil {
                SegmentedControl(
                    label: "Settings file",
                    options: [SegmentOption("Shared", value: RulesFileKind.shared), SegmentOption("Local", value: RulesFileKind.local)],
                    selection: Binding(get: { snapshot.selection.file }, set: { model.selectFile($0) })
                )
            }
            HStack(spacing: 6) {
                Text(snapshot.fileLabel).font(ReinsFont.mono)
                Text("\u{00B7}")
                Text(snapshot.selection.dir == nil ? "Applies to every project" : "Adds to Global rules")
            }
            .font(ReinsFont.small)
            .foregroundStyle(Palette.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
