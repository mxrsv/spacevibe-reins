import SwiftUI

/// The split canvas (V5-R52) of Subagents, Hooks, Rules, Activity and Limits: 32 around it; the small cards stacked 24 apart
/// in the left half, the Answer first; the spine card in the right half, 24 from it. Below 700 pt of canvas width (inside the
/// 32) both span the full width, small cards first. Layout only: the cards draw themselves.
///
/// Side by side it sizes the cards as the kit's grid does in the window: each small card takes its own height while they
/// all fit; when they do not, the room is shared out evenly, no card taking more than its own height, so the tallest ones
/// are cut and scroll inside (`Tile(maxHeight:)`). The spine stretches to the small cards' height, up to its own maximum, so
/// give it `Tile(stretches: true, maxHeight: ...)`. Whatever still does not fit (stacked, or a window too short for the
/// cards' headers) scrolls the canvas inside the panel; a headless shot cuts it at the panel instead.
///
///     SplitCanvas {
///         AnswerCard(...)
///         Tile("Next resets", maxHeight: ..., ...) { ... }
///     } spine: {
///         Tile("Usage windows", maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, ...) { ... }
///     }
struct SplitCanvas<Small: View, Spine: View>: View {
    @ViewBuilder var small: Small
    @ViewBuilder var spine: Spine

    var body: some View {
        GeometryReader { proxy in
            SpaceVibeScrollView {
                SplitCanvasLayout(room: proxy.size.height - 2 * Rhythm.edge) {
                    small
                    spine.layoutValue(key: SplitCanvasSpine.self, value: true)
                }
                .padding(Rhythm.edge)
                .modifier(ShotFit())
            }
        }
    }
}

private struct SplitCanvasSpine: LayoutValueKey {
    static let defaultValue = false
}

/// The small cards (every subview but the spine) and the spine: side by side in equal halves (the 12-column grid's two
/// spans of 6), or one under the other below `Metrics.SplitCanvas.stackBelow`.
private struct SplitCanvasLayout: Layout {
    /// The window's height for the cards, inside the canvas edge.
    let room: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let gap = Rhythm.card
        let smalls = subviews.indices.filter { !subviews[$0][SplitCanvasSpine.self] }
        let spines = subviews.indices.filter { subviews[$0][SplitCanvasSpine.self] }
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        if width < Metrics.SplitCanvas.stackBelow {
            var y: CGFloat = 0
            for index in smalls + spines {
                let height = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                frames[index] = CGRect(x: 0, y: y, width: width, height: height)
                y += height + gap
            }
            return frames
        }
        let half = max(0, (width - gap) / 2)
        let offered = Self.share(smalls.map { subviews[$0] }, width: half, room: room - gap * CGFloat(max(0, smalls.count - 1)))
        var y: CGFloat = 0
        for (index, height) in zip(smalls, offered) {
            let taken = subviews[index].sizeThatFits(ProposedViewSize(width: half, height: height)).height
            frames[index] = CGRect(x: 0, y: y, width: half, height: taken)
            y += taken + gap
        }
        let smallsHeight = max(0, y - gap)
        var spineY: CGFloat = 0
        for index in spines {
            let own = subviews[index].sizeThatFits(ProposedViewSize(width: half, height: nil)).height
            let stretched = max(smallsHeight, min(own, max(room, smallsHeight)))
            let taken = subviews[index].sizeThatFits(ProposedViewSize(width: half, height: stretched)).height
            frames[index] = CGRect(x: half + gap, y: spineY, width: half, height: taken)
            spineY += taken + gap
        }
        return frames
    }

    /// Each card's own height when they all fit `room`; otherwise the room shared out evenly, the shortest cards first, each
    /// taking no more than its own height and no less than its least (a card that cannot shrink keeps its height).
    private static func share(_ cards: [LayoutSubview], width: CGFloat, room: CGFloat) -> [CGFloat] {
        let own = cards.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        guard own.reduce(0, +) > room else { return own }
        let least = cards.map { $0.sizeThatFits(ProposedViewSize(width: width, height: 0)).height }
        var heights = own
        var left = room
        let order = own.indices.sorted { own[$0] < own[$1] }
        for (served, index) in order.enumerated() {
            heights[index] = max(least[index], min(own[index], left / CGFloat(order.count - served)))
            left -= heights[index]
        }
        return heights
    }
}
