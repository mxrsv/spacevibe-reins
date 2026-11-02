import ReinsCore
import SwiftUI

/// By day (or week, or month): paired columns of the two CLIs on one shared axis, oldest left. A bucket far above the rest
/// is cut at the axis, gets a notch and prints its value. Every column is a button that picks its bucket.
struct TokensTimelineCard: View {
    let model: TokensModel
    let board: TokensBoard
    var focus: FocusState<TokensFocus?>.Binding

    static let plotHeight: CGFloat = 206
    static let tickHeight: CGFloat = 18
    static let axisWidth: CGFloat = 44
    static let columnGap: CGFloat = 3

    private var areaHeight: CGFloat { Self.plotHeight - Self.tickHeight }

    var body: some View {
        let axis = board.axis
        TokensCard {
            TokensCardTitle(TokensFormat.seriesTitle(board.period)) {
                Text(TokensFormat.spanName(board.period))
                if axis.cut > 0 {
                    Tag("\(axis.cut) above the axis").help("The tallest bar is cut so the rest stay readable. Its value is printed on it.")
                }
                Spacer(minLength: 0)
                legend
            }
            peakLine.padding(.horizontal, 10).padding(.bottom, 8)
            plot(axis)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var legend: some View {
        if board.measure == .tokens {
            swatch(faint: false, "New")
            swatch(faint: true, "Cache reads")
        }
        TokensCLIHead(cli: .claude, size: 12)
        TokensCLIHead(cli: .codex, size: 12)
    }

    private func swatch(faint: Bool, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(Palette.textSecondary.opacity(faint ? 0.32 : 1)).frame(width: 10, height: 6)
            Text(title)
        }
    }

    private var noun: String {
        switch board.period {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        }
    }

    @ViewBuilder
    private var peakLine: some View {
        if let selected = board.selected {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                ForEach(CLIKind.allCases) { cli in
                    HStack(spacing: 6) {
                        ProviderMark(ProviderMarkKind(cli: cli), size: 15)
                        Text(TokensFormat.value(selected[cli.engine], board.measure)).font(ReinsFont.cardLeader)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(cli.label) \(TokensFormat.value(selected[cli.engine], board.measure))")
                }
                Text(board.label(selected)).font(ReinsFont.small).foregroundStyle(Palette.textTertiary)
            }
        } else if let peak = board.peak {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(TokensFormat.value(peak.both, board.measure)).font(ReinsFont.cardLeader)
                Text("highest \(noun), both CLIs: \(board.label(peak))").font(ReinsFont.small).foregroundStyle(Palette.textTertiary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Nothing counted in this period.").font(ReinsFont.small).foregroundStyle(Palette.textTertiary)
        }
    }

    private func plot(_ axis: TokensBoard.Axis) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ForEach(Array(zip([axis.top, axis.top / 2, 0], [0, areaHeight / 2, areaHeight]).enumerated()), id: \.offset) { _, mark in
                    Text(TokensFormat.axis(mark.0, board.measure))
                        .font(ReinsFont.tiny)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(height: 14)
                        .padding(.trailing, 8)
                        .offset(y: mark.1 - 7)
                }
            }
            .frame(width: Self.axisWidth, height: Self.plotHeight, alignment: .topTrailing)
            .accessibilityHidden(true)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach([0, areaHeight / 2, areaHeight], id: \.self) { y in
                        Rectangle().fill(Palette.border).frame(height: 1).offset(y: y)
                    }
                    columnsRow(width: proxy.size.width, top: axis.top)
                }
            }
            .frame(height: Self.plotHeight)
        }
    }
}

extension TokensTimelineCard {
    fileprivate struct ColumnLayout {
        let columnWidth: CGFloat
        let barWidth: CGFloat
        let every: Int
        let selectedAt: Int?

        init(width: CGFloat, count: Int, selectedAt: Int?) {
            let n = max(count, 1)
            columnWidth = (width - TokensTimelineCard.columnGap * CGFloat(n - 1)) / CGFloat(n)
            barWidth = min(12, max(2, columnWidth * 0.38))
            every = count > 20 ? 5 : count > 10 ? 2 : 1
            self.selectedAt = selectedAt
        }

        /// Every fifth (or second) bucket counted back from the newest, the picked one, and none right beside it.
        func showsTick(_ index: Int, count: Int, isSelected: Bool) -> Bool {
            if isSelected { return true }
            guard (count - 1 - index) % every == 0 else { return false }
            guard let selectedAt else { return true }
            return abs(index - selectedAt) > 1
        }
    }

    fileprivate func columnsRow(width: CGFloat, top: Double) -> some View {
        let columns = board.columns
        let layout = ColumnLayout(width: width, count: columns.count, selectedAt: columns.firstIndex { $0.id == board.selected?.id })
        return HStack(alignment: .top, spacing: Self.columnGap) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, bucket in
                column(bucket, index: index, count: columns.count, layout: layout, top: top)
            }
        }
    }

    fileprivate func column(_ bucket: TokenBucket, index: Int, count: Int, layout: ColumnLayout, top: Double) -> some View {
        let isSelected = bucket.id == board.selected?.id
        let tick: String? = layout.showsTick(index, count: count, isSelected: isSelected)
            ? TokensFormat.tick(bucket, period: board.period, timeZone: board.timeZone) : nil
        return TimelineColumn(
            bucket: bucket, label: board.label(bucket), tick: tick, measure: board.measure, top: top,
            areaHeight: areaHeight, tickHeight: Self.tickHeight, barWidth: layout.barWidth, isSelected: isSelected,
            isQuiet: board.selected != nil && !isSelected, labelLeft: Double(index) > Double(count) * 0.7, focus: focus
        ) { model.select(bucket.id) }
        .frame(width: layout.columnWidth)
    }
}

/// One bucket's column: both CLIs' bars, the cut notch and value when it rises above the axis, and the tick under it.
private struct TimelineColumn: View {
    let bucket: TokenBucket
    let label: String
    let tick: String?
    let measure: TokenMeasure
    let top: Double
    let areaHeight: CGFloat
    let tickHeight: CGFloat
    let barWidth: CGFloat
    let isSelected: Bool
    let isQuiet: Bool
    let labelLeft: Bool
    var focus: FocusState<TokensFocus?>.Binding
    let action: () -> Void

    @State private var hovering = false

    private var isOver: Bool { max(bucket.claude.value(measure), bucket.codex.value(measure)) > top }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 2) {
                    bar(.claude, bucket.claude)
                    bar(.codex, bucket.codex)
                }
                .opacity(isQuiet ? 0.45 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .frame(height: areaHeight)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
                        .fill(isSelected ? Palette.selection : hovering ? Palette.hover : .clear)
                )
                .overlay(alignment: .top) { if isOver { clipLabel } }
                tickLabel.frame(height: tickHeight)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused(focus, equals: .column(bucket.id))
        .focusEffectDisabled()
        .focusRing(focus.wrappedValue == .column(bucket.id), cornerRadius: 5)
        .onHover { hovering = $0 }
        .zIndex(isOver || isSelected ? 1 : 0)
        .help("\(label)\nClaude Code \(TokensFormat.value(bucket.claude, measure))\nCodex \(TokensFormat.value(bucket.codex, measure))")
        .accessibilityLabel("\(label), Claude Code \(TokensFormat.value(bucket.claude, measure)), Codex \(TokensFormat.value(bucket.codex, measure))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Scopes the board to this \(label)")
    }

    @ViewBuilder
    private func bar(_ cli: CLIKind, _ tally: TokenTally) -> some View {
        let value = tally.value(measure)
        if value > 0, top > 0 {
            let squeeze = min(1, top / value)
            let unit = Double(areaHeight) / top
            VStack(spacing: 1) {
                if measure == .tokens {
                    if tally.counts.cacheRead > 0 {
                        segment(cli, height: CGFloat(Double(tally.counts.cacheRead) * squeeze * unit), faint: true)
                    }
                    if tally.counts.fresh > 0 {
                        segment(cli, height: CGFloat(Double(tally.counts.fresh) * squeeze * unit), faint: false)
                    }
                } else {
                    segment(cli, height: CGFloat(value * squeeze * unit), faint: false)
                }
            }
            .overlay(alignment: .top) {
                if value > top { Rectangle().fill(Palette.surface).frame(width: barWidth + 2, height: 2).offset(y: 9) }
            }
            .frame(width: barWidth)
        } else {
            Color.clear.frame(width: barWidth, height: 0)
        }
    }

    private func segment(_ cli: CLIKind, height: CGFloat, faint: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
            .fill(cli.fill.opacity(faint ? 0.32 : 1))
            .frame(width: barWidth, height: max(1, height))
    }

    private var clipLabel: some View {
        let larger = bucket.claude.value(measure) >= bucket.codex.value(measure) ? bucket.claude : bucket.codex
        return Text(TokensFormat.value(larger, measure))
            .font(ReinsFont.tiny)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.surface))
            .fixedSize()
            .frame(width: 0, alignment: labelLeft ? .trailing : .leading)
            .offset(x: labelLeft ? -8 : 8, y: 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tickLabel: some View {
        if let tick {
            Text(tick)
                .font(isSelected ? ReinsFont.smallStrong : ReinsFont.tiny)
                .foregroundStyle(isSelected ? Palette.text : Palette.textTertiary)
                .padding(.horizontal, isSelected ? 3 : 0)
                .background(isSelected ? Palette.surface : .clear)
                .fixedSize()
                .frame(width: 0)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}
