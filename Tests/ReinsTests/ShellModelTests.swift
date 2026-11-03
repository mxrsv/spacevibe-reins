import Foundation
import Testing
@testable import Reins

extension ShellModel {
    /// A shell over the demo tabs (or the given ones) with its own throwaway defaults suite, forced dark, so no test reads
    /// or writes the real preferences.
    @MainActor
    static func forTests(tabs: [any ReinsTab]? = nil) -> ShellModel {
        let defaults = UserDefaults(suiteName: "reins-tests-\(UUID().uuidString)")!
        return ShellModel(tabs: tabs ?? DemoTabs.make(), appearance: AppearanceStore(defaults: defaults, forced: .dark))
    }
}

@MainActor
@Suite("Shell model")
struct ShellModelTests {
    @Test("the first tab is active until another is selected")
    func startsOnFirstTab() {
        #expect(ShellModel.forTests().activeID == "loadout")
    }

    @Test("selecting an id that is not a tab keeps the active tab and leaves the palette open")
    func unknownID() {
        let shell = ShellModel.forTests()
        shell.openPalette()
        shell.select("nope")
        #expect(shell.activeID == "loadout")
        #expect(shell.isPaletteOpen)
    }

    @Test("select(index:) outside the tab list does nothing", arguments: [-1, 3, 99])
    func indexOutOfRange(index: Int) {
        let shell = ShellModel.forTests()
        shell.openPalette()
        shell.select(index: index)
        #expect(shell.activeID == "loadout")
        #expect(shell.isPaletteOpen)
    }

    @Test("select(index:) picks the tab at that position, as the number shortcuts do")
    func indexInRange() {
        let shell = ShellModel.forTests()
        shell.select(index: 1)
        #expect(shell.activeID == "rules")
        shell.select(index: 2)
        #expect(shell.activeID == "activity")
    }

    @Test("choosing a tab from the open palette switches to it and closes the palette")
    func selectClosesPalette() {
        let shell = ShellModel.forTests()
        shell.openPalette(query: "rul")
        #expect(shell.isPaletteOpen)
        #expect(shell.paletteQuery == "rul")
        shell.select("rules")
        #expect(shell.activeID == "rules")
        #expect(!shell.isPaletteOpen)
    }
}
