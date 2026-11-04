import ReinsCore
import SwiftUI

/// The Agents page's components (plan A7): the inspector with a draft footer and with the discard prompt, the Markdown
/// preview, the code editor with a hidden value and with a syntax problem, the menu picker and tag menu, the choice cards
/// and a setting row. Synthetic text only.
struct AgentsSpecimens: View {
    @State private var width = Metrics.inspectorMinWidth
    @State private var text = "{\n  \"model\": \"sonnet\",\n  \"env\": { \"API_KEY\": \"\(SecretMask.placeholder)\" }\n}\n"
    @State private var broken = "{\n  \"model\": \"sonnet\",\n}\n"

    private static let markdown = "# Working rules\n\n- Answer in **Vietnamese**, keep `code` in English.\n- Run `pnpm test` before a commit.\n\n@rules/style.md\n"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(alignment: .top, spacing: Space.s16) {
                inspector(draft: 2, asks: false)
                inspector(draft: 2, asks: true)
            }
            .frame(height: Metrics.galleryOverlayHeight * 2)
            HStack(alignment: .top, spacing: Space.s16) {
                MarkdownPreview(text: Self.markdown) { _ in }
                VStack(alignment: .leading, spacing: Space.s12) {
                    CodeEditor(text: $text, hiddenCount: 1)
                    CodeEditor(text: $broken, problem: "The file is not valid JSON at line 3.")
                }
            }
            GroupedList {
                CardHeader("Controls of the panels")
                SettingRow(title: "Default mode", key: "permissions.defaultMode", note: "Claude Code will run every tool without asking.", warn: true) {
                    MenuPicker(label: "Default mode", options: [
                        MenuOption(value: "default", title: "Ask first"), MenuOption(value: "bypassPermissions", title: "Bypass", warn: true),
                    ], selection: "bypassPermissions", fill: true) { _ in }
                }
                FormRow {
                    HStack(spacing: Space.s8) {
                        TagMenu(title: "Ask", tone: .warn, moves: [(title: "Allow", action: {}), (title: "Deny", action: {})], remove: {})
                        TagMenu(title: "Forbidden", tone: .danger, moves: [(title: "Allow", action: {})])
                        Spacer(minLength: 0)
                    }
                    ChoiceCard(title: "Keep sandbox_mode", detail: "What Codex uses now. Removes default_permissions.", isOn: true) {}
                    ChoiceCard(title: "Keep the profile project-edit", detail: "Removes sandbox_mode and [sandbox_workspace_write].", isOn: false) {}
                }
            }
        }
    }

    private func inspector(draft: Int, asks: Bool) -> some View {
        InspectorPanel(cli: .claude, title: "Permissions", agent: "Claude Code", width: $width, draftCount: draft, asksToDiscard: asks,
                       close: {}, discard: {}, keepEditing: {}, review: {}) {
            HStack(spacing: Space.s8) {
                ScopePicker(options: [ScopeOption(id: nil, label: "Global")], current: ScopeOption(id: nil, label: "Global"), minWidth: Metrics.scopePickerMinWidth) { _ in }
                Text("~/.claude/settings.json").reinsText(.code, tone: .tertiary)
            }
        } content: {
            GroupedList {
                CardHeader("Rules", count: 2)
                Row { RowText("Bash(git push *)", mono: true) }.cells { Tag("Ask", tone: .warn) }
                Row { RowText("Read(.env*)", mono: true) }.cells { Tag("Deny", tone: .danger) }
            }
        }
    }
}
