import ReinsCore
import SwiftUI

/// The lead total of the whole period, then the two CLIs side by side on one scale. It never follows the scope.
struct TokensSummaryCard: View {
    let board: TokensBoard

    var body: some View {
        let measure = board.measure
        let claude = board.summary(.claude)
        let codex = board.summary(.codex)
        let both = claude + codex
        let scale = board.scale([claude, codex])
        TokensCard(padding: 0) {
            WeightedRow(weights: [1.15, 1, 1], spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(TokensFormat.spanName(board.period)).font(ReinsFont.small).foregroundStyle(Palette.textSecondary)
                    Text(TokensFormat.value(both, measure)).font(ReinsFont.leadTotal).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.6)
                    Text(detail(both, sessions: board.sessions(.claude) + board.sessions(.codex), lead: true))
                        .font(ReinsFont.tiny).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                side(.claude, claude, scale: scale)
                side(.codex, codex, scale: scale)
            }
        }
    }

    private func side(_ cli: CLIKind, _ tally: TokenTally, scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                TokensCLIHead(cli: cli, size: 16)
                if board.measure == .cost, tally.unpriced > 0 { UnpricedTag(tokens: tally.unpriced) }
            }
            .font(ReinsFont.small)
            .foregroundStyle(Palette.textSecondary)
            Text(TokensFormat.value(tally, board.measure)).font(ReinsFont.cliFigure).foregroundStyle(Palette.text).lineLimit(1)
            TokenBar(cli: cli, tally: tally, scale: scale, measure: board.measure).padding(.vertical, 3)
            Text(detail(tally, sessions: board.sessions(cli), lead: false)).font(ReinsFont.tiny).foregroundStyle(Palette.textTertiary).lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 1) }
        .accessibilityElement(children: .combine)
    }

    /// "16B tokens · 825 sessions"; with All tokens the figure already is the total, so the line gives the new part.
    private func detail(_ tally: TokenTally, sessions: Int, lead: Bool) -> String {
        let tokens = board.measure == .tokens
            ? "\(TokensFormat.tokens(tally.counts.fresh)) new\(lead ? " tokens" : "")"
            : "\(TokensFormat.tokens(tally.counts.total)) tokens"
        return "\(tokens) · \(TokensFormat.count(sessions)) \(sessions == 1 ? "session" : "sessions")"
    }
}
