import Foundation
import Testing
@testable import Reins

/// The Agents page's components (plan A7) that need no window: the inspector's width rules and footer words, the Markdown
/// preview's blocks and the code editor's status line.
@Suite("Agents components")
struct AgentsComponentTests {
    @Test("the panel drags between 420 and 720, and the cards keep 440 beside it")
    func widths() {
        #expect(InspectorWidth.clamp(100) == 420 && InspectorWidth.clamp(900) == 720 && InspectorWidth.clamp(500) == 500)
        #expect(InspectorWidth.dragged(from: 480, by: -100) == 580)
        #expect(InspectorWidth.dragged(from: 480, by: 400) == 420)
        #expect(InspectorWidth.minimumContent(panel: nil) == 440)
        #expect(InspectorWidth.minimumContent(panel: 720) == 440 + 720 + 1)
        #expect(Metrics.inspectorDefaultWidth == 480)
    }

    @Test("the preview reads headings, lists, paragraphs, code, @path lines, inline code and bold")
    func markdown() {
        let blocks = MarkdownBlock.parse("# Title\n\n- one\n- **two**\n\nA line\nwrapped.\n\n@rules/style.md\n```\ncode\n```\n")
        #expect(blocks == [.heading(level: 1, text: "Title"), .item("one"), .item("**two**"), .paragraph("A line wrapped."), .importLine("rules/style.md"), .code("code")])
        #expect(MarkdownBlock.spans("Run `pnpm test` **now**") == [.plain("Run "), .code("pnpm test"), .plain(" "), .bold("now")])
    }

    @Test("the footer and the editor's words")
    func words() {
        #expect(InspectorPanelWording.unsaved(1) == "1 unsaved change" && InspectorPanelWording.unsaved(3) == "3 unsaved changes")
        #expect(InspectorPanelWording.changes(2) == "2 changes")
        #expect(CodeEditorWording.lineCount("a\nb\n") == 2 && CodeEditorWording.lineCount("") == 1)
        #expect(CodeEditorWording.status(lines: 2, hidden: 3) == "2 lines, valid, 3 values hidden")
        #expect(CodeEditorWording.status(lines: 1, hidden: 0) == "1 line, valid")
    }
}
