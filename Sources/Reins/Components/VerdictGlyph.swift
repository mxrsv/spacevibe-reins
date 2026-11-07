import SwiftUI

/// Reins's own hexagon verdict glyphs (V5-R14, D58): the shape carries the meaning, so all five are one neutral colour
/// (`fg2`). `used` is Ran, `heavy` Ran in the top 20% tier, `never` Never ran, `nm` Unmeasurable; `dead` is not shown for
/// skills or subagents. Drawn as shapes from the kit's `v2-*` symbols (`system/shared.js`), not generated from a set.
/// Hidden from VoiceOver unless it has a `label`: a verdict also has a sentence beside it (V5-R43).
struct VerdictGlyph: View {
    enum Kind: CaseIterable {
        case heavy, used, never, dead, nm
    }

    let kind: Kind
    var size: IconSize = .control
    var label: String?

    init(_ kind: Kind, size: IconSize = .control, label: String? = nil) {
        self.kind = kind
        self.size = size
        self.label = label
    }

    var body: some View {
        let scale = size.points / Metrics.Verdict.box
        let line = StrokeStyle(lineWidth: Metrics.Verdict.stroke * scale, lineCap: .round, lineJoin: .round)
        let dashed = StrokeStyle(lineWidth: line.lineWidth, lineCap: .round, lineJoin: .round, dash: Metrics.Verdict.dash.map { $0 * scale })
        ZStack {
            switch kind {
            case .heavy:
                Part.hexagon.fill(Palette.fg2)
                Part.wideCore.fill(Palette.onVerdict)
            case .used:
                Part.hexagon.stroke(Palette.fg2, style: line)
                Part.narrowCore.fill(Palette.fg2)
            case .never:
                Part.hexagon.stroke(Palette.fg2, style: line)
            case .dead:
                Part.hexagon.stroke(Palette.fg2, style: line)
                Bolt().stroke(Palette.fg2, style: line)
            case .nm:
                Part.hexagon.stroke(Palette.fg2, style: dashed)
                Part.dot.fill(Palette.fg2)
            }
        }
        .frame(width: size.points, height: size.points)
        .modifier(VerdictAccessibility(label: label))
    }
}

/// The 16 box scaled to the rect it is given (square, centred).
private func fit(_ path: Path, in rect: CGRect) -> Path {
    let side = min(rect.width, rect.height)
    let scale = side / Metrics.Verdict.box
    return path.applying(CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: scale, y: scale))
}

private func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
    var path = Path()
    path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
    path.closeSubpath()
    return path
}

/// One drawn part of a glyph in the kit's 16 box. `hexagon` is the outer shape, `M8 1.6 13.55 4.8v6.4L8 14.4 2.45 11.2V4.8Z`.
private struct Part: Shape {
    enum Kind { case hexagon, wideCore, narrowCore, dot }
    let kind: Kind

    static let hexagon = Part(kind: .hexagon)
    static let wideCore = Part(kind: .wideCore)
    static let narrowCore = Part(kind: .narrowCore)
    static let dot = Part(kind: .dot)

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .hexagon: return fit(polygon([(8, 1.6), (13.55, 4.8), (13.55, 11.2), (8, 14.4), (2.45, 11.2), (2.45, 4.8)]), in: rect)
        case .wideCore: return fit(polygon([(8, 5.2), (10.4, 6.6), (10.4, 9.4), (8, 10.8), (5.6, 9.4), (5.6, 6.6)]), in: rect)
        case .narrowCore: return fit(polygon([(8, 5.3), (10, 6.45), (10, 8.75), (8, 10.9), (6, 9.75), (6, 7.45)]), in: rect)
        case .dot:
            let r = Metrics.Verdict.dotRadius
            return fit(Path(ellipseIn: CGRect(x: 8 - r, y: 8 - r, width: 2 * r, height: 2 * r)), in: rect)
        }
    }
}

/// `dead`'s mark, `M9.4 3.4 7 7.6l2.4 1.2-1.9 3.9`.
private struct Bolt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines([CGPoint(x: 9.4, y: 3.4), CGPoint(x: 7, y: 7.6), CGPoint(x: 9.4, y: 8.8), CGPoint(x: 7.5, y: 12.7)])
        return fit(path, in: rect)
    }
}

private struct VerdictAccessibility: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
