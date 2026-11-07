import SwiftUI

/// The SpaceVibe mark from `Resources/AppIcon.svg`, drawn as shapes (only the CLI marks are images, `IconPolicyTests`): a dark
/// rounded square with two bars and an open ring, turned 45 degrees. It leads the Settings > Update card.
struct SpaceVibeMark: View {
    var size: CGFloat = Metrics.spaceVibeMarkSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * Metrics.spaceVibeMarkRadiusFraction, style: .continuous).fill(Palette.markGround)
            ForEach(MarkPart.allCases, id: \.self) { part in
                MarkShape(part: part).fill(Palette.markInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum MarkPart: CaseIterable {
    case leftBar, rightBar, ring
}

/// One part of the mark in the SVG's 256 box, with its `translate(128 128) scale(0.9) rotate(45) translate(-128 -128)`.
/// Each part is filled on its own, so where the bars cross the ring no winding rule can cut a hole.
private struct MarkShape: Shape {
    let part: MarkPart

    private static let box: CGFloat = 256
    private static let centre = CGPoint(x: 128, y: 128)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = CGSize(width: 3.8, height: 3.8)
        switch part {
        case .leftBar: path.addRoundedRect(in: CGRect(x: 100, y: 32, width: 20, height: 192), cornerSize: corner)
        case .rightBar: path.addRoundedRect(in: CGRect(x: 136, y: 32, width: 20, height: 192), cornerSize: corner)
        case .ring:
            // Outer radius 80 and inner 54 around the centre, open at the top between x 100 and 156.
            path.move(to: CGPoint(x: 156, y: 53.06))
            path.addArc(center: Self.centre, radius: 80, startAngle: angle(156, 53.06), endAngle: angle(100, 53.06), clockwise: false)
            path.addLine(to: CGPoint(x: 100, y: 81.83))
            path.addArc(center: Self.centre, radius: 54, startAngle: angle(100, 81.83), endAngle: angle(156, 81.83), clockwise: true)
            path.closeSubpath()
        }
        let mark = CGAffineTransform(translationX: Self.centre.x, y: Self.centre.y)
            .scaledBy(x: 0.9, y: 0.9)
            .rotated(by: .pi / 4)
            .translatedBy(x: -Self.centre.x, y: -Self.centre.y)
        let fit = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / Self.box, y: rect.height / Self.box)
        return path.applying(mark.concatenating(fit))
    }

    private func angle(_ x: CGFloat, _ y: CGFloat) -> Angle {
        .radians(atan2(y - Self.centre.y, x - Self.centre.x))
    }
}
