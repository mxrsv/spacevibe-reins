import SwiftUI

/// `Stats` (V5-R58): 2 to 4 figures side by side, each a 20/28 600 figure over a 12/16 `fg3` label that names what it
/// counts and over what range. Columns are at least 88 wide and 12 apart; when they do not fit in one line they wrap.
struct StatFigures: View {
    struct Figure: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }

    let figures: [Figure]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Metrics.Stats.spacing) {
                ForEach(figures) { figure in
                    FigureView(figure: figure).frame(minWidth: Metrics.Stats.columnMinWidth, maxWidth: .infinity, alignment: .leading)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.Stats.columnMinWidth), spacing: Metrics.Stats.spacing, alignment: .leading)],
                      alignment: .leading, spacing: Metrics.Stats.spacing) {
                ForEach(figures) { FigureView(figure: $0) }
            }
        }
    }

    private struct FigureView: View {
        let figure: Figure

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(figure.value).spaceVibeText(.heading, tone: .primary).lineLimit(1).lineBox(.heading)
                Text(figure.label).spaceVibeText(.meta, tone: .tertiary).lineLimit(2).fixedSize(horizontal: false, vertical: true).lineBox(.meta)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
