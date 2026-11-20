import SwiftUI
import Testing
@testable import SpaceVibe

@MainActor
@Suite("Palette search", .fixtureCLIs)
struct PaletteSearchTests {
    private func titles(_ sections: [PaletteSection], _ section: String) -> [String]? {
        sections.first { $0.title == section }?.entries.map(\.title)
    }

    @Test("an empty query lists the tabs and the actions")
    func emptyQuery() {
        let sections = PaletteSearch.sections(shell: .forTests(), query: "")
        #expect(sections.map(\.title) == ["Go to", "Actions"])
        #expect(titles(sections, "Go to") == ["Agents", "Activity", "Limits"])
        #expect(sections.first?.entries.map(\.trailing) == ["\u{2318}1", "\u{2318}2", "\u{2318}3"])
        // The active tab's own actions come first, then the theme switch (the shell is forced dark) and Settings.
        #expect(titles(sections, "Actions") == ["Rescan usage", "Switch to light theme", "Settings"])
    }

    @Test("every word of the query must match, and a section with no match is dropped")
    func everyWordMustMatch() {
        #expect(PaletteSearch.sections(shell: .forTests(), query: "settings xyz").isEmpty)
        let sections = PaletteSearch.sections(shell: .forTests(), query: "activity")
        #expect(sections.map(\.title) == ["Go to"])
    }

    @Test("matching ignores case and also reads keywords")
    func caseAndKeywords() {
        let sections = PaletteSearch.sections(shell: .forTests(), query: "PREFERENCES")
        #expect(titles(sections, "Actions") == ["Settings"])
    }

    @Test("the newest Undo of the session is an action with the Z cap, and runs it")
    func undoAction() throws {
        let toasts = ToastCenter(announce: false)
        var ran: [String] = []
        toasts.show("a", undo: { ran.append("a") })
        toasts.show("x", tone: .danger)
        var actions = try #require(PaletteSearch.sections(shell: .forTests(), toasts: toasts, query: "").first { $0.title == "Actions" }).entries
        #expect(actions.map(\.title).contains("Undo: a"))
        toasts.show("b", undo: { ran.append("b") })
        actions = try #require(PaletteSearch.sections(shell: .forTests(), toasts: toasts, query: "").first { $0.title == "Actions" }).entries
        // Only the newest item is offered, so Undo stays last in, first out.
        #expect(actions.filter { $0.id == "shell.undo" }.map(\.title) == ["Undo: b"])
        let undo = try #require(actions.first { $0.id == "shell.undo" })
        #expect(undo.trailing == "Z")
        undo.perform()
        #expect(ran == ["b"])
    }

    @MainActor
    @Test("\"countdown\" and \"weekly\" find Settings > Limits, and choosing it opens Settings there")
    func findsWeeklyCountdown() throws {
        let shell = ShellModel.forTests()
        for query in ["countdown", "weekly", "limits settings"] {
            let titles = PaletteSearch.sections(shell: shell, query: query).flatMap(\.entries).map(\.title)
            #expect(titles.contains("Weekly countdown"), "\(query)")
        }
        let entry = try #require(PaletteSearch.sections(shell: shell, query: "countdown").flatMap(\.entries).first { $0.title == "Weekly countdown" })
        entry.perform()
        #expect(shell.isSettingsOpen && shell.settingsSection == .limits)
    }

    @Test("no Undo action while the stack is empty or no center is given")
    func noUndoWithoutItems() {
        let titles = { (toasts: ToastCenter?) in
            PaletteSearch.sections(shell: .forTests(), toasts: toasts, query: "").flatMap(\.entries).map(\.title)
        }
        #expect(!titles(ToastCenter(announce: false)).contains { $0.hasPrefix("Undo") })
        #expect(!titles(nil).contains { $0.hasPrefix("Undo") })
    }
}
