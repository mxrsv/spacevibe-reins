import CoreGraphics
import Testing
@testable import Reins

/// The ten-cell ruler (spec `docs/specs/2026-11-03-reins-design-language.md`, v3 "Progress", DL8): each cell is a tenth of the
/// real track width with the 3 pt gap at its trailing end, the filled cells take the share, the last filled one is cut at it,
/// and an unknown share draws the dashed outline.
@Suite("Ruler")
struct RulerTests {
    /// The usage cell's track: 200 wide, less 12 of spacing and the 52 pt number.
    static let usageTrack: CGFloat = 136

    private func cells(_ share: Double?, width: CGFloat = usageTrack) -> [RulerCell] {
        guard case .cells(let cells) = RulerLayout.make(share: share, width: width) else {
            Issue.record("expected cells for \(String(describing: share))")
            return []
        }
        return cells
    }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

    @Test("a cell is a tenth of the track, gap included, at the usage track and at any other width")
    func cellComesFromTheTrack() {
        for width in [Self.usageTrack, 200, 91] {
            let laid = cells(0.5, width: width)
            #expect(laid.count == 10)
            let pitch = width / 10
            for (index, cell) in laid.enumerated() {
                #expect(close(cell.x, CGFloat(index) * pitch))
                #expect(close(cell.width, pitch - Metrics.rulerCellGap))
            }
        }
        #expect(close(cells(0.5)[0].width, 10.6))
    }

    @Test("0 percent fills nothing")
    func zero() {
        #expect(cells(0).allSatisfy { $0.filled == 0 })
    }

    @Test("4 percent fills four tenths of the first cell and nothing after it")
    func four() {
        let laid = cells(0.04)
        #expect(close(laid[0].filled, laid[0].width * 0.4))
        #expect(laid.dropFirst().allSatisfy { $0.filled == 0 })
    }

    @Test("39 percent fills three cells and cuts the fourth at nine tenths")
    func thirtyNine() {
        let laid = cells(0.39)
        for cell in laid.prefix(3) { #expect(close(cell.filled, cell.width)) }
        #expect(close(laid[3].filled, laid[3].width * 0.9))
        #expect(laid.dropFirst(4).allSatisfy { $0.filled == 0 })
    }

    @Test("100 percent fills every cell, and a share past either end is clamped")
    func full() {
        #expect(cells(1).allSatisfy { close($0.filled, $0.width) })
        #expect(cells(1.7) == cells(1))
        #expect(cells(-0.2) == cells(0))
    }

    @Test("an unknown share draws the dashed outline, never empty cells")
    func unknown() {
        #expect(RulerLayout.make(share: nil, width: Self.usageTrack) == .outline)
        #expect(RulerLayout.make(share: .nan, width: Self.usageTrack) == .outline)
    }
}
