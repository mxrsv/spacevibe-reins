import SwiftUI

/// The permanent detail pane (V5-R33, V5-R34): head, description, verdict, sessions by CLI, the files the skill lives in and
/// the actions. Counts live only here (V5-R31). Every sentence is `SkillsWording`'s.
struct SkillsPane: View {
    let model: SkillsModel
    let row: LoadoutRow?
    let detected: [CoreCLI]
    let status: SkillStatus
    let scopeLabel: String
    let now: Date

    private enum Action: Hashable { case add, remove, open }

    @FocusState private var actionFocus: Action?

    var body: some View {
        if let row {
            pane(row)
        } else {
            QuietEmptyState("Nothing selected", message: "Pick a row on the left.", placement: .list)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func pane(_ row: LoadoutRow) -> some View {
        let writable = row.plugin == nil && row.project == nil
        return DetailPane {
            PaneHead(name: row.name, glyph: CategoryGlyph.skill, tone: .skill, pluginTag: row.plugin.map { "plugin: \($0)" },
                     meta: ["Skill", scopeLabel]) {
                LogoStrip {
                    ForEach(detected, id: \.self) { cli in
                        LogoToggle(cli: CoreLimitsCLI(cli), isLit: row.members[cli] != nil, mode: model.mode(row, cli: cli),
                                   justChanged: model.changed.contains("\(row.key):\(cli.rawValue)")) { model.toggle(row, cli: cli) }
                    }
                }
            }
            if !row.detail.isEmpty {
                Text(row.detail).spaceVibeText(.prose, tone: .secondary).fixedSize(horizontal: false, vertical: true).lineBox(.prose)
            }
            if let verdict = SkillsWording.verdict(for: row, status: status, detected: detected) {
                VerdictBox(glyph: status.verdict, glyphLabel: verdict.title, title: verdict.title, text: verdict.text, small: verdict.small)
            }
            PaneSection(title: "Sessions by CLI") {
                SessionMeters(meters: detected.map { SkillsWording.meter(for: row, cli: $0, maxSessions: model.maxSessions, now: now) })
            }
            PaneSection(title: "Lives in") {
                FileList(files: model.files(of: row).map { FileList.Entry(cli: $0.cli, path: $0.path) })
            }
            VStack(alignment: .leading, spacing: Metrics.DetailPane.noteAbove) {
                HStack(spacing: Metrics.DetailPane.actionSpacing) {
                    ForEach(detected.filter { row.members[$0] == nil && model.mode(row, cli: $0) == .toggles }, id: \.self) { cli in
                        Button { model.add([row], to: cli) } label: { ActionLabel("Add to \(cli.label)", key: "A") }
                            .buttonStyle(ActionButtonStyle(kind: .primary))
                            .focused($actionFocus, equals: .add)
                    }
                    Button { model.remove([row]) } label: { ActionLabel("Remove", glyph: .trash, key: "R") }
                        .buttonStyle(ActionButtonStyle(kind: .danger))
                        .disabled(!writable)
                        .focused($actionFocus, equals: .remove)
                    Button { model.openFile(of: row) } label: { ActionLabel("Open", glyph: .open, key: "O") }
                        .buttonStyle(ActionButtonStyle())
                        .focused($actionFocus, equals: .open)
                }
                if let plugin = row.plugin {
                    PopoverNote("Owned by the \(plugin) plugin. Remove it by uninstalling the plugin.", glyph: .lock)
                } else if row.project != nil {
                    PopoverNote("This skill belongs to a project. SpaceVibe can read it but not change it.", glyph: .lock)
                }
            }
        }
        .onChange(of: model.paneFocusRequest) { _, _ in
            // Return puts the keyboard on the first action that can run (V5-R36).
            let canAdd = detected.contains { row.members[$0] == nil && model.mode(row, cli: $0) == .toggles }
            actionFocus = canAdd ? .add : (writable ? .remove : .open)
        }
    }
}
