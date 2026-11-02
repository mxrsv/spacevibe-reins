import ReinsCore
import SwiftUI

/// Cache reuse: the share of each CLI's tokens in scope that were cache reads, with a composition strip.
struct TokensCacheCard: View {
    let board: TokensBoard

    var body: some View {
        TokensCard {
            TokensCardTitle("Cache reuse") {
                Spacer(minLength: 0)
                Text("reused")
            }
            WeightedRow(weights: [1, 1], spacing: 14) {
                part(.claude)
                part(.codex)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private func part(_ cli: CLIKind) -> some View {
        let tally = board.scoped(cli)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                ProviderMark(ProviderMarkKind(cli: cli), size: 16)
                Text(tally.cacheShare.map(TokensFormat.percent) ?? "–").font(ReinsFont.cardLeader)
            }
            strip(cli, tally)
            Text(tally.isEmpty ? "No tokens in this scope" : "\(TokensFormat.tokens(tally.counts.cacheRead)) cached · \(TokensFormat.tokens(tally.counts.fresh)) new")
                .font(ReinsFont.tiny)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(TokensFormat.kindsTip(tally))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tally.isEmpty ? "\(cli.label): no tokens in this scope"
            : "\(cli.label): \(TokensFormat.percent(tally.cacheShare ?? 0)) reused, \(TokensFormat.tokens(tally.counts.cacheRead)) cached, \(TokensFormat.tokens(tally.counts.fresh)) new")
    }

    private func strip(_ cli: CLIKind, _ tally: TokenTally) -> some View {
        GeometryReader { proxy in
            let total = Double(max(tally.counts.total, 1))
            let room = max(proxy.size.width - 2, 0)
            HStack(spacing: 2) {
                if tally.isEmpty {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.track)
                } else {
                    if tally.counts.cacheRead > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(cli.fill.opacity(0.32))
                            .frame(width: max(3, room * CGFloat(Double(tally.counts.cacheRead) / total)))
                    }
                    if tally.counts.fresh > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(cli.fill)
                            .frame(width: max(3, room * CGFloat(Double(tally.counts.fresh) / total)))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: Metrics.barHeight)
        .padding(.vertical, 1)
    }
}

/// Estimated cost: an accounting table of the priced models, the tokens with no price, and the sum, with the price table.
struct TokensCostCard: View {
    @Bindable var model: TokensModel
    let board: TokensBoard
    @Environment(\.isShotRendering) private var isShotRendering

    static let valueWidth: CGFloat = 96

    var body: some View {
        let claude = board.scoped(.claude)
        let codex = board.scoped(.codex)
        let both = claude + codex
        TokensCard {
            TokensCardTitle("Estimated cost") {
                Spacer(minLength: 0)
                priceButton
            }
            VStack(spacing: 0) {
                line(height: 22, top: false) {
                    Color.clear
                } claude: {
                    TokensCLIHead(cli: .claude, size: 12, short: true)
                } codex: {
                    TokensCLIHead(cli: .codex, size: 12, short: true)
                }
                .font(ReinsFont.small)
                .foregroundStyle(Palette.textTertiary)
                line {
                    Text("Priced models").foregroundStyle(Palette.textSecondary)
                } claude: { priced(claude) } codex: { priced(codex) }
                line {
                    Text("Tokens with no price").foregroundStyle(Palette.textSecondary)
                } claude: { unpriced(claude) } codex: { unpriced(codex) }
                HStack {
                    Text("Both").font(ReinsFont.bodyStrong)
                    Spacer(minLength: 0)
                    Text(both.cost.map(TokensFormat.usd) ?? "–").font(ReinsFont.cardLeader)
                }
                .frame(height: 30)
                .overlay(alignment: .top) { Hairline() }
                .accessibilityElement(children: .combine)
            }
            .font(ReinsFont.compact)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        // Headless screenshots cannot draw a popover, so they draw the price table in place under its button.
        .overlay(alignment: .topTrailing) {
            if isShotRendering, model.isPriceTableOpen {
                TokensPriceTable(unpriced: board.unpricedModels).overlayPanel().fixedSize().offset(x: -14, y: 38)
            }
        }
    }

    private func line<L: View, A: View, B: View>(height: CGFloat = 26, top: Bool = true, @ViewBuilder _ label: () -> L,
                                                 @ViewBuilder claude: () -> A, @ViewBuilder codex: () -> B) -> some View {
        HStack(spacing: 0) {
            label().frame(maxWidth: .infinity, alignment: .leading)
            claude().frame(width: Self.valueWidth, alignment: .trailing)
            codex().frame(width: Self.valueWidth, alignment: .trailing)
        }
        .lineLimit(1)
        .frame(height: height)
        .overlay(alignment: .top) { if top { Hairline() } }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func priced(_ tally: TokenTally) -> some View {
        if tally.isEmpty {
            Text("–").foregroundStyle(Palette.textTertiary)
        } else if let usd = tally.cost {
            Text(TokensFormat.usd(usd))
        } else {
            Tag("no price")
        }
    }

    private func unpriced(_ tally: TokenTally) -> some View {
        Text(tally.unpriced > 0 ? TokensFormat.tokens(tally.unpriced) : "0").foregroundStyle(tally.unpriced > 0 ? Palette.text : Palette.textTertiary)
    }

    private var priceButton: some View {
        Button("Price table \u{00B7} \(TokensPriceTable.latestFetch)") { model.isPriceTableOpen.toggle() }
            .buttonStyle(.reins(.normal))
            .accessibilityHint("Shows the prices behind the estimate")
            .popover(isPresented: isShotRendering ? .constant(false) : $model.isPriceTableOpen, arrowEdge: .bottom) {
                TokensPriceTable(unpriced: board.unpricedModels).padding(2)
            }
    }
}

/// USD per million tokens from `Pricing`, and the models in scope that have no price.
struct TokensPriceTable: View {
    let unpriced: [String]

    static let width: CGFloat = 430

    private static func dayText(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return iso }
        return TokensFormat.short(LocalDay(year: parts[0], month: parts[1], day: parts[2]), TimeZone(identifier: "UTC")!)
    }

    /// "Nov 3": the newest fetch in the table.
    static var latestFetch: String { Pricing.fetchedAt.values.max().map(dayText) ?? "" }

    private static var fetchRange: String {
        let days = Set(Pricing.fetchedAt.values).sorted()
        guard let first = days.first, let last = days.last else { return "" }
        return first == last ? dayText(first) : "\(dayText(first)) to \(dayText(last))"
    }

    private struct Row: Identifiable {
        let name: String
        let price: ModelPrice
        var id: String { name }
    }

    /// Claude models first, then the others, each by name.
    private var models: [Row] {
        Pricing.models.map { Row(name: $0.key, price: $0.value) }.sorted { a, b in
            let (ca, cb) = (a.name.hasPrefix("claude"), b.name.hasPrefix("claude"))
            return ca != cb ? ca : a.name < b.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Price table").font(ReinsFont.bodyStrong)
            Text("USD per million tokens. API list prices, fetched \(Self.fetchRange). Not what a subscription costs.")
                .font(ReinsFont.small).foregroundStyle(Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow {
                    Text("Model").gridColumnAlignment(.leading)
                    Text("Input")
                    Text("Cache read")
                    Text("Cache write")
                    Text("Output")
                }
                .foregroundStyle(Palette.textTertiary)
                .frame(height: 22)
                ForEach(models) { row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text(row.name)
                        Text(Self.rate(row.price.input))
                        Text(Self.rate(row.price.cacheRead))
                        Text(Self.rate(row.price.cacheWrite))
                        Text(Self.rate(row.price.output))
                    }
                    .frame(height: 26)
                }
                ForEach(unpriced, id: \.self) { name in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text(name)
                        Tag("no price").gridCellColumns(4)
                    }
                    .frame(height: 26)
                }
            }
            .font(ReinsFont.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: Self.width, alignment: .leading)
        // A popover takes the environment of its button, which sits in a one-line, muted card title.
        .lineLimit(nil)
        .foregroundStyle(Palette.text)
    }

    /// "$4", "$0.2", "$0.125"
    static func rate(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "$" + text
    }

    /// The look of an overlay panel, for the in-place copy in headless screenshots.
    func overlayPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return self
            .background(shape.fill(Palette.surface))
            .overlay(shape.strokeBorder(Palette.border, lineWidth: 1))
            .shadow(color: Palette.overlayShadow, radius: 20, y: 14)
    }
}
