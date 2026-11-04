import SwiftUI

/// Every page glyph (Tabler) at 14, 16, 20 and 24, in the secondary tone, then in a tag's warn ink. Pages draw only these.
struct PageIconSpecimens: View {
    private let sizes: [IconSize] = [.inline, .control, .row, .large]

    var body: some View {
        GroupedList {
            ForEach(Array(PageGlyph.allCases.enumerated()), id: \.offset) { _, glyph in
                HStack(spacing: Metrics.rowSpacing) {
                    Text(glyph.tablerName).reinsText(.code, tone: .tertiary).frame(width: Metrics.usageCellWidth * 1.5, alignment: .leading)
                    ForEach(Array(sizes.enumerated()), id: \.offset) { _, size in
                        PageIcon(glyph, size: size).frame(width: Metrics.iconLarge)
                    }
                    PageIcon(glyph, size: .control, ink: Palette.warnInk)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Metrics.rowHorizontalPadding)
            }
        }
    }
}

/// Every sidebar glyph (Solar Bold Duotone) at 14, 16, 20 and 22, in the secondary tone, then in the warn ink of the
/// Limits tile's stale clock. Only the sidebar's items and footer draw these.
struct SidebarIconSpecimens: View {
    private let sizes: [IconSize] = [.inline, .control, .row, .sidebar]

    var body: some View {
        GroupedList {
            ForEach(Array(ReinsGlyph.allCases.enumerated()), id: \.offset) { _, glyph in
                HStack(spacing: Metrics.rowSpacing) {
                    Text(glyph.solarName).reinsText(.code, tone: .tertiary).frame(width: Metrics.usageCellWidth * 1.5, alignment: .leading)
                    ForEach(Array(sizes.enumerated()), id: \.offset) { _, size in
                        ReinsIcon(glyph, size: size).frame(width: Metrics.iconLarge)
                    }
                    ReinsIcon(glyph, size: .control, ink: Palette.warnInk)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Metrics.rowHorizontalPadding)
            }
        }
    }
}
