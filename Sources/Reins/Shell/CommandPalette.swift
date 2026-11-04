import SwiftUI

/// The `⌘K` overlay: a search field and grouped results. Up and Down move the highlight, Return runs it, Esc closes.
///
/// Accessibility: SwiftUI has no combobox role, so the field is a search field described as controlling the
/// results, each result is a button that reports whether it is highlighted, and the result count is announced
/// as the query changes.
struct CommandPalette: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.isShotRendering) private var isShotRendering
    @State private var highlightedID: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        @Bindable var shell = shell
        let sections = PaletteSearch.sections(shell: shell, query: shell.paletteQuery)
        let flat = sections.flatMap(\.entries)
        let current = flat.contains { $0.id == highlightedID } ? highlightedID : flat.first?.id

        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Scrim { shell.closePalette() }
                panel(sections: sections, flat: flat, current: current, query: $shell.paletteQuery)
                    .padding(.top, proxy.size.height * Metrics.paletteTopFraction)
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

    private func panel(sections: [PaletteSection], flat: [PaletteEntry], current: String?, query: Binding<String>) -> some View {
        PaletteCard {
            field(flat: flat, current: current, query: query)
            Hairline()
            results(sections: sections, flat: flat, current: current)
            Hairline()
            footer
        }
    }

    private func field(flat: [PaletteEntry], current: String?, query: Binding<String>) -> some View {
        let placeholder = "Search skills, hooks, rules, or run an action"
        return Group {
            if isShotRendering {
                // ImageRenderer cannot draw a TextField; draw what it would show.
                Text(query.wrappedValue.isEmpty ? placeholder : query.wrappedValue)
                    .foregroundStyle((query.wrappedValue.isEmpty ? TextTone.tertiary : TextTone.primary).color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: query, prompt: Text(placeholder).foregroundStyle(TextTone.tertiary.color))
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
        .paletteField()
        .accessibilityLabel("Search commands")
        .accessibilityValue(query.wrappedValue)
        .accessibilityHint("\(flat.count) results. Use up and down arrows, then Return.")
        .accessibilityAddTraits(.isSearchField)
    }

    private func results(sections: [PaletteSection], flat: [PaletteEntry], current: String?) -> some View {
        let height = min(Metrics.paletteListMaxHeight, CGFloat(flat.count) * Metrics.paletteRowHeight + CGFloat(sections.count) * Metrics.paletteSectionHeight + Space.s12)
        return ScrollViewReader { proxy in
            ReinsScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if flat.isEmpty { PaletteEmptyRow(text: "No matches") }
                    ForEach(sections) { section in
                        PaletteSectionTitle(title: section.title)
                        ForEach(section.entries) { entry in
                            PaletteRow(entry: entry, isHighlighted: entry.id == current) { run(entry) }
                                .id(entry.id)
                        }
                    }
                }
                .paletteList()
            }
            .frame(height: max(height, Metrics.rowMinHeight))
            .onChange(of: current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var footer: some View {
        PaletteFooter {
            PaletteHint(text: "navigate") { PageIcon(.navigate, size: .inline) }
            PaletteHint(text: "run") { PageIcon(.enter, size: .inline) }
            PaletteHint(text: "close") { Kbd("Esc") }
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
