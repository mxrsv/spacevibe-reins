import SwiftUI

/// The dimmed layer behind an overlay (the palette, a confirmation). A click on it runs `onTap`.
struct Scrim: View {
    let onTap: () -> Void

    var body: some View {
        Palette.overlay
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityHidden(true)
    }
}

/// The command palette's card: 600 pt wide, radius 12, the one place besides confirmations with a shadow.
struct PaletteCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.paletteRadius, style: .continuous)
        VStack(spacing: 0) { content }
            .frame(width: Metrics.paletteWidth)
            .background(shape.fill(Palette.surface))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
            .shadow(color: Palette.overlayShadow, radius: Metrics.overlayShadowRadius, y: Metrics.overlayShadowOffset)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Command palette")
            .accessibilityAddTraits(.isModal)
    }
}

extension View {
    /// The palette's search line: `paletteInput` type, 48 pt high.
    func paletteField() -> some View {
        reinsText(.paletteInput, tone: .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s16)
            .frame(height: Metrics.paletteFieldHeight)
    }

    /// The scrolling list of results: 6 pt inside the card's edge.
    func paletteList() -> some View {
        padding(Space.s6)
    }
}

/// A group title in the palette list: "Skills", "Actions".
struct PaletteSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .reinsText(.label, tone: .tertiary)
            .padding(.horizontal, Space.s8)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "No matches" in the palette list.
struct PaletteEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .reinsText(.body, tone: .tertiary)
            .padding(.horizontal, Space.s8)
            .frame(height: Metrics.paletteRowHeight)
    }
}

/// One result: icon, title, muted subtitle and trailing text; the highlighted one on the selection tint.
struct PaletteRow: View {
    let entry: PaletteEntry
    let isHighlighted: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.fieldRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: Space.s8) {
                if let systemImage = entry.systemImage {
                    Image(systemName: systemImage)
                        .frame(width: Metrics.sidebarIconWidth)
                        .accessibilityHidden(true)
                }
                Text(entry.title).lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle).reinsText(.caption, tone: .tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let trailing = entry.trailing {
                    Text(trailing).reinsText(.caption, tone: .tertiary)
                }
            }
            .reinsText(.body, tone: isHighlighted ? .primary : .secondary)
            .padding(.horizontal, Space.s8)
            .frame(height: Metrics.paletteRowHeight)
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

/// The palette's bottom line of key hints.
struct PaletteFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Space.s16) {
            content
            Spacer(minLength: 0)
        }
        .reinsText(.caption, tone: .tertiary)
        .padding(.horizontal, Space.s16)
        .frame(height: Metrics.paletteFooterHeight)
        .accessibilityHidden(true)
    }
}

/// A glyph and its word in the palette footer: "↑↓ navigate".
struct PaletteHint<Glyph: View>: View {
    let text: String
    @ViewBuilder var glyph: Glyph

    var body: some View {
        HStack(spacing: Space.s6) {
            glyph
            Text(text)
        }
    }
}
