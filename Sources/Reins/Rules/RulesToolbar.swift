import SwiftUI

/// The scope picker (Global or a discovered project), the Shared / Local switch for a project, and the file the scope means.
struct RulesToolbar: View {
    let model: RulesModel
    let snapshot: RulesSnapshot

    var body: some View {
        HStack(spacing: 10) {
            RulesScopePicker(model: model, snapshot: snapshot)
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

/// A menu in the app; headless screenshots cannot draw one, so they get the closed label.
private struct RulesScopePicker: View {
    let model: RulesModel
    let snapshot: RulesSnapshot
    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        if isShotRendering {
            label
        } else {
            Menu {
                choice("Global", dir: nil)
                ForEach(snapshot.projects, id: \.dir) { project in
                    choice(project.name, dir: project.dir)
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .reinsFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityLabel("Scope")
            .accessibilityValue(name)
        }
    }

    private var name: String {
        guard let dir = snapshot.selection.dir else { return "Global" }
        return snapshot.projects.first { $0.dir == dir }?.name ?? "Project"
    }

    private func choice(_ title: String, dir: String?) -> some View {
        Button {
            model.selectProject(dir)
        } label: {
            if dir == snapshot.selection.dir { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        return HStack(spacing: 8) {
            Text(name).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(Palette.textTertiary).accessibilityHidden(true)
        }
        .font(ReinsFont.body)
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 10)
        .frame(minWidth: 130, alignment: .leading)
        .frame(height: Metrics.controlHeight)
        .background(shape.fill(Palette.surface))
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .contentShape(shape)
    }
}
