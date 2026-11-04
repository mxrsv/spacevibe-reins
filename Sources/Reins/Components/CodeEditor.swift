import SwiftUI

/// The Advanced panel's editor (spec, Interface: Advanced): the whole settings file in the `code` role with line numbers in a
/// gutter, on a `surface` block. The text it gets is already masked by `SecretMask`, so a secret reads `••••` and never
/// reaches it. `problem` is the syntax check's sentence ("not valid JSON at line 14"), shown under the editor in the danger
/// tone; while it is set, the panel blocks Save. Headless shots get the text it would show.
struct CodeEditor: View {
    @Binding var text: String
    var problem: String?
    var hiddenCount = 0

    @Environment(\.isShotRendering) private var isShotRendering
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            editor
            HStack(spacing: Space.s8) {
                if let problem {
                    PageIcon(.error, size: .inline, ink: Palette.dangerInk)
                    Text(problem).reinsText(.caption, tone: .danger)
                } else {
                    PageIcon(.check, size: .inline, ink: Palette.successInk)
                    Text(CodeEditorWording.status(lines: CodeEditorWording.lineCount(text), hidden: hiddenCount)).reinsText(.caption, tone: .tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var editor: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(1...max(1, CodeEditorWording.lineCount(text)), id: \.self) { line in
                    Text("\(line)").reinsText(.count, tone: .tertiary).frame(height: Metrics.codeLineHeight)
                }
            }
            .padding(.leading, Space.s12)
            .padding(.trailing, Space.s8)
            .frame(minWidth: Metrics.gutterWidth, alignment: .trailing)
            .accessibilityHidden(true)
            Group {
                if isShotRendering {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line).reinsText(.code, tone: .primary).lineLimit(1).frame(height: Metrics.codeLineHeight)
                        }
                    }
                } else {
                    TextEditor(text: $text)
                        .reinsText(.code, tone: .primary)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .frame(minHeight: CGFloat(CodeEditorWording.lineCount(text)) * Metrics.codeLineHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.trailing, Space.s16)
        }
        .padding(.vertical, Space.s12)
        .background(shape.fill(Palette.surface))
        .focusRing(focused, cornerRadius: Metrics.groupRadius)
        .accessibilityLabel("Settings file")
    }
}

/// The editor's words. Pure, so the tests pin them.
enum CodeEditorWording {
    static func lineCount(_ text: String) -> Int {
        text.isEmpty ? 1 : text.components(separatedBy: "\n").count - (text.hasSuffix("\n") ? 1 : 0)
    }

    static func status(lines: Int, hidden: Int) -> String {
        let base = lines == 1 ? "1 line" : "\(lines) lines"
        guard hidden > 0 else { return "\(base), valid" }
        return "\(base), valid, \(hidden == 1 ? "1 value" : "\(hidden) values") hidden"
    }
}
