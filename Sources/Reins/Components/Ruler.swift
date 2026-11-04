import SwiftUI

/// One cell of a ruler, in points from the track's leading edge.
struct RulerCell: Equatable {
    let x: CGFloat
    let width: CGFloat
    /// How much of the cell is filled from its leading edge, 0 to `width`.
    let filled: CGFloat
}

/// Where a ruler's cells sit for a share at a track width. Pure, so `RulerTests` pins it (DL8).
enum RulerLayout: Equatable {
    /// The share is not known: a dashed outline the width of the track.
    case outline
    case cells([RulerCell])

    /// Each cell is a tenth of `width`, with the gap at its trailing end, so the cell follows the real track and is never a
    /// constant. A share of 0.39 fills three cells and nine tenths of the fourth; a share outside 0...1 is clamped.
    static func make(share: Double?, width: CGFloat, count: Int = Metrics.rulerCellCount, gap: CGFloat = Metrics.rulerCellGap) -> RulerLayout {
        guard let share, share.isFinite else { return .outline }
        let pitch = max(0, width) / CGFloat(count)
        let cellWidth = max(0, pitch - gap)
        let filledCells = CGFloat(min(1, max(0, share))) * CGFloat(count)
        return .cells((0..<count).map { index in
            let part = min(1, max(0, filledCells - CGFloat(index)))
            return RulerCell(x: CGFloat(index) * pitch, width: cellWidth, filled: cellWidth * part)
        })
    }
}

/// The Limits progress display, used nowhere else (Loadout and Activity keep the continuous `UsageBar`): ten square-ended
/// cells, 8 pt high, 3 pt apart, as wide as the space it is given. Filled cells take `fill` and the last filled one is cut
/// at the share; empty cells are `surfaceRaised`. An unknown share (`nil`) draws a dashed
/// outline instead ("not counted yet", a window past its reset). Decorative: the number beside it carries the meaning.
struct Ruler: View {
    /// 0 to 1, or nil when not known.
    let share: Double?
    let fill: Color

    var body: some View {
        GeometryReader { proxy in
            switch RulerLayout.make(share: share, width: proxy.size.width) {
            case .outline:
                Rectangle()
                    .strokeBorder(Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: proxy.size.width, height: Metrics.rulerHeight)
            case .cells(let cells):
                ZStack(alignment: .topLeading) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        Rectangle()
                            .fill(Palette.surfaceRaised)
                            .overlay(alignment: .leading) { Rectangle().fill(fill).frame(width: cell.filled) }
                            .frame(width: cell.width, height: Metrics.rulerHeight)
                            .offset(x: cell.x)
                    }
                }
                .frame(width: proxy.size.width, height: Metrics.rulerHeight, alignment: .topLeading)
            }
        }
        .frame(height: Metrics.rulerHeight)
        .accessibilityHidden(true)
    }
}
