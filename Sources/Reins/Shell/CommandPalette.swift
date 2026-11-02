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
                Palette.overlay
                    .contentShape(Rectangle())
                    .onTapGesture { shell.closePalette() }
                    .accessibilityHidden(true)
                panel(sections: sections, flat: flat, current: current, query: $shell.paletteQuery)
                    .padding(.top, proxy.size.height * 0.14)
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
        let shape = RoundedRectangle(cornerRadius: Metrics.paletteRadius, style: .continuous)
        return VStack(spacing: 0) {
            field(flat: flat, current: current, query: query)
            Hairline()
            results(sections: sections, flat: flat, current: current)
            Hairline()
            footer
        }
        .frame(width: 600)
        .background(shape.fill(Palette.surface))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
        .shadow(color: Palette.overlayShadow, radius: 30, y: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
        .accessibilityAddTraits(.isModal)
    }

    private func field(flat: [PaletteEntry], current: String?, query: Binding<String>) -> some View {
        let placeholder = "Search skills, hooks, rules, or run an action"
        return Group {
            if isShotRendering {
                // ImageRenderer cannot draw a TextField; draw what it would show.
                Text(query.wrappedValue.isEmpty ? placeholder : query.wrappedValue)
                    .foregroundStyle(query.wrappedValue.isEmpty ? Palette.textTertiary : Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: query, prompt: Text(placeholder).foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.text)
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
        .font(ReinsFont.palette)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .accessibilityLabel("Search commands")
        .accessibilityValue(query.wrappedValue)
        .accessibilityHint("\(flat.count) results. Use up and down arrows, then Return.")
        .accessibilityAddTraits(.isSearchField)
    }

    private func results(sections: [PaletteSection], flat: [PaletteEntry], current: String?) -> some View {
        let height = min(360, CGFloat(flat.count) * 36 + CGFloat(sections.count) * 26 + 12)
        return ScrollViewReader { proxy in
            ReinsScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if flat.isEmpty {
                        Text("No matches")
                            .font(ReinsFont.body)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                    }
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(ReinsFont.tiny)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.entries) { entry in
                            PaletteRow(entry: entry, isHighlighted: entry.id == current) { run(entry) }
                                .id(entry.id)
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: max(height, 48))
            .onChange(of: current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint { Image(systemName: "arrow.up.arrow.down") } text: { "navigate" }
            hint { Image(systemName: "return") } text: { "run" }
            hint { Kbd("Esc") } text: { "close" }
            Spacer(minLength: 0)
        }
        .font(ReinsFont.small)
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .accessibilityHidden(true)
    }

    private func hint<Glyph: View>(@ViewBuilder glyph: () -> Glyph, text: () -> String) -> some View {
        HStack(spacing: 6) {
            glyph()
            Text(text())
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

private struct PaletteRow: View {
    let entry: PaletteEntry
    let isHighlighted: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage = entry.systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 18)
                        .foregroundStyle(isHighlighted ? Palette.text : Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(entry.title).lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle).font(ReinsFont.small).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let trailing = entry.trailing {
                    Text(trailing).font(ReinsFont.small).foregroundStyle(Palette.textTertiary)
                }
            }
            .font(ReinsFont.body)
            .foregroundStyle(isHighlighted ? Palette.text : Palette.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(shape.fill(isHighlighted ? Palette.selection : (hovering ? Palette.hover : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityLabel([entry.title, entry.subtitle, entry.trailing].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
