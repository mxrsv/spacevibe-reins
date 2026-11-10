import Foundation
import Testing
@testable import SpaceVibe

extension ShellModel {
    /// A shell over the demo tabs (or the given ones) with its own throwaway defaults suite, forced dark, so no test reads
    /// or writes the real preferences.
    @MainActor
    static func forTests(tabs: [any SpaceVibeTab]? = nil) -> ShellModel {
        let defaults = UserDefaults(suiteName: "spacevibe-tests-\(UUID().uuidString)")!
        return ShellModel(tabs: tabs ?? DemoTabs.make(), appearance: AppearanceStore(defaults: defaults, forced: .dark))
    }

    /// The v5 shell over the v5 registry (Agents, Activity, Limits), with a throwaway env so no test reaches the real core.
    static func forV5Tests() -> ShellModel {
        let defaults = UserDefaults(suiteName: "spacevibe-tests-\(UUID().uuidString)")!
        return ShellModel(tabs: TabRegistry.makeTabs(isV5: true), appearance: AppearanceStore(defaults: defaults, forced: .dark), isV5: true)
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

    @Test("Settings closes the palette, keeps the tab under it, and anything that picks a page closes it")
    func settingsOpenAndClose() {
        let shell = ShellModel.forTests()
        shell.select("rules")
        shell.openPalette()
        shell.openSettings()
        #expect(shell.isSettingsOpen && !shell.isPaletteOpen)
        #expect(shell.title == "Rules")
        shell.closeSettings()
        #expect(!shell.isSettingsOpen && shell.activeID == "rules")
        shell.openSettings()
        shell.select(index: 0)
        #expect(!shell.isSettingsOpen && shell.activeID == "loadout")
        shell.openSettings()
        shell.openLimits()
        #expect(!shell.isSettingsOpen && shell.isLimitsOpen)
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

    @Test("the Limits page takes the content area, the title and the hints until a tab is chosen, and keeps the active tab")
    func limitsPage() {
        let shell = ShellModel.forTests()
        shell.select("rules")
        shell.openPalette()
        shell.openLimits()
        #expect(shell.isLimitsOpen)
        #expect(!shell.isPaletteOpen)
        #expect(shell.title == LimitsPage.title)
        #expect(shell.hints == LimitsPage.hints)
        #expect(shell.activeID == "rules")
        shell.select("activity")
        #expect(!shell.isLimitsOpen)
        #expect(shell.title == "Activity")
        #expect(shell.hints == shell.activeTab.hints)
    }

    // MARK: v5 shell (V5-R49, V5-R36, V5-R37)

    @Test("the v5 registry is Agents, Activity and Limits; the old one is unchanged")
    func v5Registry() {
        #expect(TabRegistry.makeTabs(isV5: true).map(\.id) == ["agents", "activity", "limits"])
        #expect(TabRegistry.makeTabs(isV5: true).map(\.title) == ["Agents", "Activity", "Limits"])
        #expect(TabRegistry.makeTabs().map(\.id) == ["loadout", "rules", "activity"])
        #expect(!ShellModel.forTests().isV5 && ShellModel.forV5Tests().isV5)
    }

    @Test("⌘1 to ⌘3 pick Agents, Activity and Limits; a fourth index does nothing")
    func v5NumberShortcuts() {
        let shell = ShellModel.forV5Tests()
        #expect(shell.activeID == "agents")
        shell.select(index: 1)
        #expect(shell.activeID == "activity")
        shell.select(index: 2)
        #expect(shell.activeID == "limits")
        shell.select(index: 3)
        #expect(shell.activeID == "limits")
        shell.select(index: 0)
        #expect(shell.activeID == "agents")
    }

    @Test("in v5 Limits is a tab: opening it selects the tab and never raises the old page")
    func v5LimitsIsATab() {
        let shell = ShellModel.forV5Tests()
        shell.openSettings()
        shell.openLimits()
        #expect(shell.activeID == "limits" && !shell.isLimitsOpen && !shell.isSettingsOpen)
        #expect(shell.title == "Limits")
    }

    @Test("Settings opens from the footer over the page, which keeps its place, and a page pick closes it")
    func v5Settings() {
        let shell = ShellModel.forV5Tests()
        shell.select("activity")
        shell.openSettings()
        #expect(shell.isSettingsOpen && shell.activeID == "activity")
        shell.select(index: 0)
        #expect(!shell.isSettingsOpen && shell.activeID == "agents")
    }

    @Test("the search row and ⌘K open the palette, a command closes it, and the palette lists real commands only")
    func v5Palette() throws {
        let shell = ShellModel.forV5Tests()
        shell.openPalette()
        #expect(shell.isPaletteOpen)
        let sections = PaletteSearch.sections(shell: shell, query: "")
        #expect(sections.map(\.title) == ["Go to", "Actions"])
        #expect(sections.first?.entries.map(\.title) == ["Agents", "Activity", "Limits"])
        #expect(sections.first?.entries.map(\.trailing) == ["\u{2318}1", "\u{2318}2", "\u{2318}3"])
        #expect(sections.last?.entries.map(\.title) == ["Refresh", "Switch to light theme", "Settings"])
        #expect(sections.flatMap(\.entries).allSatisfy { $0.glyph != nil })
        let limits = try #require(sections.first?.entries.last)
        limits.perform()
        #expect(shell.activeID == "limits" && !shell.isPaletteOpen)
        shell.togglePalette()
        shell.togglePalette()
        #expect(!shell.isPaletteOpen)
    }

    @Test("the product name has one source: the constant the sidebar, the window and the update lines read")
    func productName() {
        #expect(SpaceVibeMark.productName == "SpaceVibe")
        #expect(SettingsWording.appName(version: nil) == SpaceVibeMark.productName)
        #expect(SettingsWording.appName(version: "0.2.0") == "\(SpaceVibeMark.productName) 0.2.0")
    }
}
