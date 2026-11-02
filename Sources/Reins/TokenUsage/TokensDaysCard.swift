import ReinsCore
import SwiftUI

/// Days (or weeks, or months): one row of exact values per bucket, newest first. A row picks its bucket; its chevron
/// opens the four token kinds of both CLIs.
struct TokensDaysCard: View {
    let model: TokensModel
    let board: TokensBoard
    var focus: FocusState<TokensFocus?>.Binding

    static let nameWidth: CGFloat = 170
    static let costWidth: CGFloat = 92

    var body: some View {
        let buckets = board.buckets
        let scale = board.scale(buckets.flatMap { [$0.claude, $0.codex] })
        TokensCard {
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text(TokensFormat.rowsTitle(board.period)).font(ReinsFont.bodyStrong).foregroundStyle(Palette.text)
                    Text("\(buckets.count)")
                }
                .frame(width: Self.nameWidth, alignment: .leading)
                TokensCLIHead(cli: .claude).frame(maxWidth: .infinity, alignment: .leading)
                TokensCLIHead(cli: .codex).frame(maxWidth: .infinity, alignment: .leading)
                Text("Est. cost").frame(width: Self.costWidth, alignment: .trailing)
            }
            .font(ReinsFont.small)
            .foregroundStyle(Palette.textTertiary)
            .frame(minHeight: 30)
            .padding(.horizontal, 10)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(buckets) { bucket in
                BucketRow(bucket: bucket, label: board.label(bucket), measure: board.measure, scale: scale,
                          isSelected: bucket.id == board.selected?.id, isOpen: model.expanded.contains(bucket.id), focus: focus,
                          select: { model.select(bucket.id) }, toggle: { model.toggleExpanded(bucket.id) })
            }
        }
    }
}

private struct BucketRow: View {
    let bucket: TokenBucket
    let label: String
    let measure: TokenMeasure
    let scale: Double
    let isSelected: Bool
    let isOpen: Bool
    var focus: FocusState<TokensFocus?>.Binding
    let select: () -> Void
    let toggle: () -> Void

    @State private var hovering = false
    @FocusState private var chevronFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Button(action: toggle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($chevronFocused)
                    .focusEffectDisabled()
                    .focusRing(chevronFocused, cornerRadius: 4)
                    .accessibilityLabel(isOpen ? "Hide token kinds for \(label)" : "Show token kinds for \(label)")
                    Text(label).foregroundStyle(Palette.text).lineLimit(1)
                }
                .frame(width: TokensDaysCard.nameWidth, alignment: .leading)
                Button(action: select) {
                    HStack(spacing: 16) {
                        cell(.claude, bucket.claude)
                        cell(.codex, bucket.codex)
                        cost.frame(width: TokensDaysCard.costWidth, alignment: .trailing)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused(focus, equals: .row(bucket.id))
                .focusEffectDisabled()
                .accessibilityLabel("\(label), Claude Code \(TokensFormat.value(bucket.claude, measure)), Codex \(TokensFormat.value(bucket.codex, measure))")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Scopes the board to \(label)")
            }
            .font(ReinsFont.compact)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? Palette.selection : hovering ? Palette.hover : .clear))
            .focusRing(focus.wrappedValue == .row(bucket.id), cornerRadius: 6, inset: true)
            .onHover { hovering = $0 }
            if isOpen { kinds }
        }
    }

    private func cell(_ cli: CLIKind, _ tally: TokenTally) -> some View {
        HStack(spacing: 10) {
            if measure == .cost, !tally.isEmpty, tally.cost == nil {
                Spacer(minLength: 0)
            } else {
                TokenBar(cli: cli, tally: tally, scale: scale, measure: measure)
            }
            TokensValue(tally: tally, measure: measure).frame(width: 74, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .help(TokensFormat.kindsTip(tally))
    }

    @ViewBuilder
    private var cost: some View {
        let both = bucket.both
        if both.isEmpty {
            Text("–").foregroundStyle(Palette.textTertiary)
        } else if let usd = both.cost {
            HStack(spacing: 4) {
                Text(TokensFormat.usd(usd))
                if both.unpriced > 0 {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(Palette.warnInk)
                        .help("\(TokensFormat.tokens(both.unpriced)) tokens use a model with no price")
                }
            }
        } else {
            Text("not measured").foregroundStyle(Palette.textTertiary)
        }
    }

    private var kinds: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Token kinds").font(ReinsFont.small).foregroundStyle(Palette.textTertiary).padding(.top, 4)
                .frame(width: TokensDaysCard.nameWidth, alignment: .leading)
            TokenKindsList(tally: bucket.claude).frame(maxWidth: .infinity)
            TokenKindsList(tally: bucket.codex).frame(maxWidth: .infinity)
            Color.clear.frame(width: TokensDaysCard.costWidth, height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.background))
        .padding(.top, 2)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Token kinds for \(label)")
    }
}
