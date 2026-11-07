import Foundation
import Testing
@testable import SpaceVibe

/// How the split canvas shares the window's height among the small cards (V5-R52, V5-A22): the result never depends on the
/// order of the cards, and fills the room exactly unless the cards fit or cannot shrink enough.
@Suite("Split canvas")
struct SplitCanvasTests {
    @Test("cards that fit keep their own heights")
    func fits() {
        #expect(SplitCanvasShare.heights(own: [197, 202, 251], least: [197, 52, 52], room: 700) == [197, 202, 251])
    }

    @Test("a card that cannot shrink keeps its height and the others split what is left evenly, in any order")
    func oneCannotShrink() {
        // The Answer (no maximum, so its least is its own height) between two cards that scroll inside.
        #expect(SplitCanvasShare.heights(own: [202, 238, 251], least: [52, 238, 52], room: 455) == [108.5, 238, 108.5])
        #expect(SplitCanvasShare.heights(own: [238, 251, 202], least: [238, 52, 52], room: 455) == [238, 108.5, 108.5])
        #expect(SplitCanvasShare.heights(own: [251, 202, 238], least: [52, 52, 238], room: 455) == [108.5, 108.5, 238])
    }

    @Test("a card shorter than the even share keeps its own height; the taller ones share the rest")
    func shortKeepsOwn() {
        let heights = SplitCanvasShare.heights(own: [197, 332, 250], least: [197, 52, 52], room: 672)
        #expect(heights == [197, 237.5, 237.5])
        #expect(heights.reduce(0, +) == 672)
    }

    @Test("when even the leasts do not fit, every card takes its least and the canvas scrolls")
    func leastsOverflow() {
        #expect(SplitCanvasShare.heights(own: [200, 300], least: [150, 250], room: 300) == [150, 250])
    }
}
