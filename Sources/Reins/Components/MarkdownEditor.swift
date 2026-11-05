import SwiftUI

/// One block of a Markdown file as the Rules panel's Preview draws it (spec, Interface: Rules). Pure, so the tests pin it.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case item(String)
    case paragraph(String)
    /// A line that is only `@path`: a row that opens that file.
    case importLine(String)
    case code(String)

    /// Headings (`#` to `######`), list items (`-`, `*`, `+`, `1.`), fenced code, `@path` lines and paragraphs (lines
    /// joined until a blank line).
    static func parse(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: [String]?
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if let open = fence { out.append(.code(open.joined(separator: "\n"))); fence = nil } else { flush(); fence = [] }
                continue
            }
            if fence != nil { fence?.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if let level = headingLevel(line) {
                flush()
                out.append(.heading(level: level, text: String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("@"), line.count > 1, !line.contains(" ") {
                flush()
                out.append(.importLine(String(line.dropFirst())))
            } else if let item = listItem(line) {
                flush()
                out.append(.item(item))
            } else {
                paragraph.append(line)
            }
        }
        if let open = fence { out.append(.code(open.joined(separator: "\n"))) }
        flush()
        return out
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.count > hashes, line[line.index(line.startIndex, offsetBy: hashes)] == " " else { return nil }
        return hashes
    }

    private static func listItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) { return String(line.dropFirst(2)) }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") { return String(line.dropFirst(digits.count + 2)) }
        return nil
    }

    /// Inline spans: `code` and **bold**, everything else plain.
    enum Span: Equatable {
        case plain(String), bold(String), code(String)
    }

    static func spans(_ text: String) -> [Span] {
        var out: [Span] = []
        for (index, part) in text.components(separatedBy: "`").enumerated() where !part.isEmpty {
            if index % 2 == 1 { out.append(.code(part)); continue }
            for (inner, piece) in part.components(separatedBy: "**").enumerated() where !piece.isEmpty {
                out.append(inner % 2 == 1 ? .bold(piece) : .plain(piece))
            }
        }
        return out
    }
}

/// The Rules panel's Preview: headings in `title` and `bodyStrong`, paragraphs and list items in `body` with inline code in
/// the `code` role and bold in `bodyStrong`, fenced code in a raised block, and each `@path` line a row that opens the file.
struct MarkdownPreview: View {
    let text: String
    var openImport: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding(.horizontal, Space.s24)
        .padding(.top, Space.s8)
        .padding(.bottom, Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous).fill(Palette.surface))
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text).reinsText(level == 1 ? .title : .bodyStrong, tone: .primary).padding(.top, Space.s12)
        case .paragraph(let text):
            inline(text).fixedSize(horizontal: false, vertical: true)
        case .item(let text):
            HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                Text("\u{2022}").reinsText(.body, tone: .tertiary)
                inline(text).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let text):
            Text(text)
                .reinsText(.code, tone: .primary)
                .padding(Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(Palette.surfaceRaised))
        case .importLine(let path):
            Button { openImport?(path) } label: {
                HStack(spacing: Space.s12) {
                    PageIcon(.link, size: .row).foregroundStyle(Palette.textSecondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Imports").reinsText(.caption, tone: .tertiary)
                        Text(path).reinsText(.codeTitle, tone: .primary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    PageIcon(.arrowRight).foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, Space.s12)
                .padding(.vertical, Space.s8)
                .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(Palette.surfaceRaised))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .reinsFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityLabel("Open \(path)")
        }
    }

    private func inline(_ text: String) -> Text {
        MarkdownBlock.spans(text).reduce(Text("")) { result, span in
            switch span {
            case .plain(let s): return result + Text(s).reinsText(.body, tone: .secondary)
            case .bold(let s): return result + Text(s).reinsText(.bodyStrong, tone: .primary)
            case .code(let s): return result + Text(s).reinsText(.codeTitle, tone: .primary)
            }
        }
    }
}

/// The Rules panel's editor: the file's text in `body`, Edit or Preview. Headless shots cannot draw a text editor, so they
/// get the text it would show. An empty file shows the empty state, whose action starts editing.
struct MarkdownEditor: View {
    @Binding var text: String
    let isEditing: Bool
    var openImport: ((String) -> Void)?
    let startEditing: () -> Void

    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        if !isEditing && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            GroupedList {
                EmptyState("This file is empty", message: "Instructions you write here load at the start of every session.", icon: .file) {
                    Button { startEditing() } label: { ButtonLabel("Start writing", icon: .edit) }.buttonStyle(.reins(.normal))
                }
            }
        } else if isEditing {
            TextEditorBox(text: $text, role: .body, isShotRendering: isShotRendering)
        } else {
            MarkdownPreview(text: text, openImport: openImport)
        }
    }
}

/// A multi-line editor on a `surface` block, radius 12: AppKit's text view in the app, the plain text in a shot.
struct TextEditorBox: View {
    @Binding var text: String
    let role: ReinsType
    let isShotRendering: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
        Group {
            if isShotRendering {
                Text(text).reinsText(role, tone: .primary).frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                TextEditor(text: $text)
                    .reinsText(role, tone: .primary)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .autocorrectionDisabled()
            }
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, minHeight: Metrics.editorMinHeight, alignment: .topLeading)
        .background(shape.fill(Palette.surface))
        .focusRing(focused, cornerRadius: Metrics.groupRadius)
    }
}
