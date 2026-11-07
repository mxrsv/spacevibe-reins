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

/// The Limits progress display, used nowhere else (Loadout and Activity keep the continuous `UsageBar`): ten square cells,
/// 3 pt apart, as wide as the space it is given; 8 pt high in the window list, `rulerDetailHeight` under the figure. Only the
/// two outer ends round (the first cell's leading corners, the last cell's trailing ones), by a quarter of the height.
/// Filled cells take `fill` and the last filled one is cut at the share; empty cells are `track` (since the v5 values,
/// `surfaceRaised` on a light card is too close to white to show them), or `trackOnSelection` on a selected tile. An unknown share (`nil`) draws a dashed outline with the same ends instead ("not
/// counted yet", a window past its reset). Decorative: the number beside it carries the meaning.
struct Ruler: View {
    /// 0 to 1, or nil when not known.
    let share: Double?
    let fill: Color
    var height: CGFloat = Metrics.rulerHeight
    var emptyFill: Color = Palette.track

    var body: some View {
        let radius = height * Metrics.rulerEndRadiusFraction
        GeometryReader { proxy in
            switch RulerLayout.make(share: share, width: proxy.size.width) {
            case .outline:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: proxy.size.width, height: height)
            case .cells(let cells):
                ZStack(alignment: .topLeading) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(emptyFill)
                            Rectangle().fill(fill).frame(width: cell.filled)
                        }
                        .frame(width: cell.width, height: height)
                        .clipShape(Self.cellShape(first: index == 0, last: index == cells.count - 1, radius: radius))
                        .offset(x: cell.x)
                    }
                }
                .frame(width: proxy.size.width, height: height, alignment: .topLeading)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Square, except the ruler's two outer ends.
    private static func cellShape(first: Bool, last: Bool, radius: CGFloat) -> UnevenRoundedRectangle {
        let lead = first ? radius : 0
        let trail = last ? radius : 0
        return UnevenRoundedRectangle(topLeadingRadius: lead, bottomLeadingRadius: lead, bottomTrailingRadius: trail,
                                      topTrailingRadius: trail, style: .continuous)
    }
}
