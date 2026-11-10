import SwiftUI
import Testing
@testable import SpaceVibe

/// A tab that only supplies palette items, so the cap can be reached without piling up demo content.
@MainActor
private final class ItemsTab: SpaceVibeTab {
    let id = "stub"
    let title = "Stub"
    let icon = SpaceVibeGlyph.info
    let paletteItems: [PaletteEntry]
    init(items: [PaletteEntry]) { paletteItems = items }
    var content: AnyView { AnyView(EmptyView()) }
}

@MainActor
@Suite("Palette search")
struct PaletteSearchTests {
    private func titles(_ sections: [PaletteSection], _ section: String) -> [String]? {
        sections.first { $0.title == section }?.entries.map(\.title)
    }

    @Test("an empty query lists the tabs and the actions, and no items")
    func emptyQuery() {
        let sections = PaletteSearch.sections(shell: .forTests(), query: "")
        #expect(sections.map(\.title) == ["Go to", "Actions"])
        #expect(titles(sections, "Go to") == ["Loadout", "Rules", "Activity"])
        #expect(sections.first?.entries.map(\.trailing) == ["\u{2318}1", "\u{2318}2", "\u{2318}3"])
        // The active tab's own actions come first, then the theme switch (the shell is forced dark) and Settings.
        #expect(titles(sections, "Actions") == ["Rescan usage", "Switch to light theme", "Settings"])
    }

    @Test("a word that matches an item lists it under Items with the tab title as its subtitle")
    func itemGetsTabTitle() throws {
        let sections = PaletteSearch.sections(shell: .forTests(), query: "pony")
        #expect(sections.map(\.title) == ["Items"])
        let entry = try #require(sections.first?.entries.first)
        #expect(entry.title == "ponytail")
        #expect(entry.subtitle == "Loadout")
    }

    @Test("every word of the query must match, and a section with no match is dropped")
    func everyWordMustMatch() {
        let sections = PaletteSearch.sections(shell: .forTests(), query: "pony xyz")
        #expect(titles(sections, "Items") == nil)
        #expect(sections.isEmpty)
    }

    @Test("matching ignores case and also reads keywords")
    func caseAndKeywords() {
        let sections = PaletteSearch.sections(shell: .forTests(), query: "PONY SKILL")
        #expect(titles(sections, "Items") == ["ponytail"])
    }

    @Test("an item keeps its own subtitle")
    func ownSubtitle() {
        let items = [
            PaletteEntry(id: "stub.own", title: "alpha entry", subtitle: "Mine") {},
            PaletteEntry(id: "stub.plain", title: "beta entry") {},
        ]
        let shell = ShellModel.forTests(tabs: [ItemsTab(items: items)])
        let entries = PaletteSearch.sections(shell: shell, query: "entry").first?.entries
        #expect(entries?.map(\.subtitle) == ["Mine", "Stub"])
    }

    @Test("a query that matches more items than the limit lists only the first ones up to the limit")
    func itemLimit() {
        let items = (0..<(PaletteSearch.itemLimit + 5)).map { n in
            PaletteEntry(id: "stub.\(n)", title: "widget \(n)") {}
        }
        let shell = ShellModel.forTests(tabs: [ItemsTab(items: items)])
        let listed = titles(PaletteSearch.sections(shell: shell, query: "widget"), "Items")
        #expect(listed?.count == PaletteSearch.itemLimit)
        #expect(listed?.first == "widget 0")
        #expect(listed?.last == "widget \(PaletteSearch.itemLimit - 1)")
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

    @Test("no Undo action while the stack is empty or no center is given")
    func noUndoWithoutItems() {
        let titles = { (toasts: ToastCenter?) in
            PaletteSearch.sections(shell: .forTests(), toasts: toasts, query: "").flatMap(\.entries).map(\.title)
        }
        #expect(!titles(ToastCenter(announce: false)).contains { $0.hasPrefix("Undo") })
        #expect(!titles(nil).contains { $0.hasPrefix("Undo") })
    }
}
