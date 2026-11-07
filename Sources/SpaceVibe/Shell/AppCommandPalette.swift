import SwiftUI

/// The v5 `⌘K` overlay (V5-R37): the 560 wide palette on the scrim, 112 below the window's top. It lists real commands only
/// (`PaletteSearch`): the pages with `⌘1` to `⌘3`, Settings and the appearance switch. Up and Down move the highlight, Return
/// runs it, Esc closes. As in the old palette the field is a search field that controls the results, each result is a button
/// that says whether it is highlighted, and the result count is announced as the query changes.
struct AppCommandPalette: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.isShotRendering) private var isShotRendering
    @State private var highlightedID: String?
    @FocusState private var fieldFocused: Bool

    private static let placeholder = "Type a command\u{2026}"
    private static let footer = [
        KeyHint(keys: "\u{2191} \u{2193}", label: "move"),
        KeyHint(keys: "\u{21B5}", label: "run"),
        KeyHint(keys: "Esc", label: "close"),
    ]

    var body: some View {
        @Bindable var shell = shell
        let sections = PaletteSearch.sections(shell: shell, query: shell.paletteQuery)
        let flat = sections.flatMap(\.entries)
        let current = flat.contains { $0.id == highlightedID } ? highlightedID : flat.first?.id

        PaletteStage(onDismiss: { shell.closePalette() }) {
            PalettePanel {
                PaletteSearchLine { field(flat: flat, current: current, query: $shell.paletteQuery) }
                results(sections: sections, current: current)
                PaletteKeysFooter(hints: Self.footer)
            }
        }
        .onAppear {
            fieldFocused = true
            highlightedID = flat.first?.id
        }
        .onChange(of: shell.paletteQuery) { _, _ in highlightedID = nil }
        .onChange(of: flat.count) { _, count in
            AccessibilityNotification.Announcement(count == 0 ? "No results" : "\(count) results").post()
        }
        .onExitCommand { shell.closePalette() }
    }

    private func field(flat: [PaletteEntry], current: String?, query: Binding<String>) -> some View {
        Group {
            if isShotRendering {
                // ImageRenderer cannot draw a TextField; draw what it would show.
                Text(query.wrappedValue.isEmpty ? Self.placeholder : query.wrappedValue)
                    .foregroundStyle((query.wrappedValue.isEmpty ? TextTone.tertiary : TextTone.primary).color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: query, prompt: Text(Self.placeholder).foregroundStyle(TextTone.tertiary.color))
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { if let entry = flat.first(where: { $0.id == current }) { run(entry) } }
                    .onKeyPress(.downArrow) { move(1, in: flat, from: current) }
                    .onKeyPress(.upArrow) { move(-1, in: flat, from: current) }
                    .onKeyPress(.escape) {
                        shell.closePalette()
                        return .handled
                    }
            }
        }
        .accessibilityLabel("Search commands")
        .accessibilityValue(query.wrappedValue)
        .accessibilityHint("\(flat.count) results. Use up and down arrows, then Return.")
        .accessibilityAddTraits(.isSearchField)
    }

    private func results(sections: [PaletteSection], current: String?) -> some View {
        ScrollViewReader { proxy in
            SpaceVibeScrollView {
                PaletteCommandList {
                    if sections.isEmpty { PaletteNoMatch() }
                    ForEach(sections) { section in
                        PaletteGroupTitle(section.title)
                        ForEach(section.entries) { entry in
                            PaletteCommandRow(title: entry.title, glyph: entry.glyph, keyCap: entry.trailing, isSelected: entry.id == current) { run(entry) }
                                .id(entry.id)
                        }
                    }
                }
            }
            .paletteListHeight()
            .onChange(of: current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func move(_ step: Int, in flat: [PaletteEntry], from current: String?) -> KeyPress.Result {
        guard !flat.isEmpty else { return .handled }
        let index = flat.firstIndex { $0.id == current } ?? 0
        highlightedID = flat[(index + step + flat.count) % flat.count].id
        return .handled
    }

    private func run(_ entry: PaletteEntry) {
        shell.closePalette()
        entry.perform()
    }
}
