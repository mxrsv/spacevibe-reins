import Foundation

struct PaletteSection: Identifiable {
    let title: String
    let entries: [PaletteEntry]

    var id: String { title }
}

/// Builds what the palette lists: "Go to" (the tabs), "Actions" (the active tab's, plus global ones) and, once
/// the user has typed something, "Items" (every tab's searchable items). Matching is case-insensitive and every
/// word of the query must appear in the title, subtitle or keywords.
@MainActor
enum PaletteSearch {
    static let itemLimit = 30

    static func sections(shell: ShellModel, query: String) -> [PaletteSection] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)

        let goTo = shell.tabs.enumerated().map { index, tab in
            PaletteEntry(
                id: "goto.\(tab.id)",
                title: tab.title,
                systemImage: tab.systemImage,
                trailing: "\u{2318}\(index + 1)",
                keywords: ["go to"]
            ) { shell.select(tab.id) }
        }

        let theme = shell.appearance.choice.toggled
        let global = PaletteEntry(
            id: "shell.theme",
            title: "Switch to \(theme.rawValue) theme",
            systemImage: theme == .light ? "sun.max" : "moon",
            keywords: ["appearance", "dark", "light", "mode"]
        ) { shell.appearance.toggle() }
        let actions = shell.activeTab.paletteActions + [global]

        var sections = [
            PaletteSection(title: "Go to", entries: goTo.filter { matches($0, words) }),
            PaletteSection(title: "Actions", entries: actions.filter { matches($0, words) }),
        ]
        if !words.isEmpty {
            let items = shell.tabs.flatMap { tab in
                tab.paletteItems.map { entry -> PaletteEntry in
                    var copy = entry
                    if copy.subtitle == nil { copy.subtitle = tab.title }
                    return copy
                }
            }
            sections.append(PaletteSection(title: "Items", entries: Array(items.filter { matches($0, words) }.prefix(itemLimit))))
        }
        return sections.filter { !$0.entries.isEmpty }
    }

    private static func matches(_ entry: PaletteEntry, _ words: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        let haystack = ([entry.title, entry.subtitle ?? ""] + entry.keywords).joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}
