import ReinsCore
import SwiftUI

/// Children side by side with widths in proportion to `weights` (fixed widths where `fixed` names one), all as tall as
/// the tallest, like the mock's grid rows (`align-items: stretch`).
struct WeightedRow: Layout {
    var weights: [CGFloat]
    var fixed: [Int: CGFloat] = [:]
    var spacing: CGFloat = 12

    private func widths(_ total: CGFloat, count: Int) -> [CGFloat] {
        let gaps = spacing * CGFloat(max(count - 1, 0))
        let fixedSum = (0..<count).compactMap { fixed[$0] }.reduce(0, +)
        let flexible = (0..<count).filter { fixed[$0] == nil }
        let weightSum = flexible.map { $0 < weights.count ? weights[$0] : 1 }.reduce(0, +)
        let room = max(total - gaps - fixedSum, 0)
        return (0..<count).map { index in
            if let width = fixed[index] { return width }
            let weight = index < weights.count ? weights[index] : 1
            return weightSum > 0 ? room * weight / weightSum : 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 1000
        let columnWidths = widths(total, count: subviews.count)
        let height = zip(subviews, columnWidths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, count: subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

/// One card of the board: the surface, its border, and room for the content. Elevation is the border, never a shadow.
struct TokensCard<Content: View>: View {
    var padding: CGFloat = 4
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(Palette.surface))
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
            .accessibilityElement(children: .contain)
    }
}

/// A card's first line: its name in the body colour, then small muted words and controls.
struct TokensCardTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(ReinsFont.bodyStrong).foregroundStyle(Palette.text).accessibilityAddTraits(.isHeader)
            trailing
        }
        .font(ReinsFont.small)
        .foregroundStyle(Palette.textTertiary)
        .lineLimit(1)
        .frame(minHeight: 30)
        .padding(.horizontal, 10)
    }
}

extension TokensCardTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// A mark and a CLI's name, muted: the head of a column or lane.
struct TokensCLIHead: View {
    let cli: CLIKind
    var size: CGFloat = 13
    var short = false

    var body: some View {
        HStack(spacing: 6) {
            ProviderMark(ProviderMarkKind(cli: cli), size: size)
            Text(short ? (cli == .claude ? "Claude" : "Codex") : cli.label)
        }
        .lineLimit(1)
    }
}

/// A horizontal bar on a track. With `tokens` the new tokens are solid and the cache reads faint, so a bar shows both;
/// other measures draw one fill. `flip` grows it from the right, for the left half of a mirrored row.
struct TokenBar: View {
    let cli: CLIKind
    let tally: TokenTally
    let scale: Double
    let measure: TokenMeasure
    var height: CGFloat = Metrics.barHeight
    var track = true
    var flip = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 2) {
                if flip { Spacer(minLength: 0) }
                if measure == .tokens {
                    if flip { segment(Double(tally.counts.cacheRead), width: width, faint: true) }
                    segment(Double(tally.counts.fresh), width: width, faint: false)
                    if !flip { segment(Double(tally.counts.cacheRead), width: width, faint: true) }
                } else {
                    segment(tally.value(measure), width: width, faint: false)
                }
                if !flip { Spacer(minLength: 0) }
            }
            .frame(width: width, height: height)
            .background {
                if track { RoundedRectangle(cornerRadius: height / 2).fill(Palette.track) }
            }
            .clipShape(RoundedRectangle(cornerRadius: height / 2))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segment(_ amount: Double, width: CGFloat, faint: Bool) -> some View {
        if amount > 0, scale > 0 {
            RoundedRectangle(cornerRadius: height / 2)
                .fill(cli.fill.opacity(faint ? 0.32 : 1))
                .frame(width: max(2, width * CGFloat(min(amount / scale, 1))), height: height)
        }
    }
}

/// "616M unpriced": tokens on a model with no price, left out of the estimate next to it.
struct UnpricedTag: View {
    let tokens: Int

    var body: some View {
        Tag("\(TokensFormat.tokens(tokens)) unpriced", tone: .warn, systemImage: "exclamationmark.triangle")
            .help("Tokens on a model with no price, not in this estimate")
    }
}

/// The value of a tally for the measure; "no price" as a tag, and a warning sign when part of the tokens has no price.
struct TokensValue: View {
    let tally: TokenTally
    let measure: TokenMeasure
    var font: Font = ReinsFont.compact

    var body: some View {
        if !tally.isEmpty, measure == .cost, tally.cost == nil {
            Tag("no price")
        } else {
            HStack(spacing: 4) {
                Text(TokensFormat.value(tally, measure))
                    .font(font)
                    .foregroundStyle(tally.isEmpty ? Palette.textTertiary : Palette.text)
                if TokensFormat.isPartial(tally, measure) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.warnInk)
                        .help("\(TokensFormat.tokens(tally.unpriced)) tokens use a model with no price")
                        .accessibilityLabel("\(TokensFormat.tokens(tally.unpriced)) tokens have no price")
                }
            }
            .lineLimit(1)
        }
    }
}

/// The four kinds of one tally, for an opened bucket row.
struct TokenKindsList: View {
    let tally: TokenTally

    var body: some View {
        VStack(spacing: 1) {
            kind("Input", tally.counts.input)
            kind("Cache write", tally.counts.cacheWrite)
            kind("Cache read", tally.counts.cacheRead)
            kind("Output", tally.counts.output)
        }
    }

    private func kind(_ name: String, _ value: Int) -> some View {
        HStack(spacing: 12) {
            Text(name).foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
            Text(TokensFormat.tokens(value)).foregroundStyle(Palette.text)
        }
        .font(ReinsFont.compact)
        .frame(height: 24)
        .accessibilityElement(children: .combine)
    }
}
