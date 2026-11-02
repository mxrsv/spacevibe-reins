import ReinsCore
import SwiftUI

/// Models: one ranked lane per CLI, the leader larger, the tail folded behind a button. A row picks its model.
struct TokensModelsCard: View {
    let model: TokensModel
    let board: TokensBoard

    static let shown = 4

    var body: some View {
        TokensCard {
            TokensCardTitle("Models")
            WeightedRow(weights: [1, 1], spacing: 10) {
                lane(.claude)
                lane(.codex)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private func lane(_ cli: CLIKind) -> some View {
        let list = board.models(cli)
        let open = model.unfolded.contains(cli.rawValue)
        let rows = open ? list : Array(list.prefix(Self.shown))
        let scale = board.scale(list.map(\.tally))
        return VStack(alignment: .leading, spacing: 0) {
            TokensCLIHead(cli: cli)
                .font(ReinsFont.small)
                .foregroundStyle(Palette.textSecondary)
                .frame(height: 22)
                .padding(.horizontal, 2)
            if rows.isEmpty {
                Text("No model in this scope").font(ReinsFont.small).foregroundStyle(Palette.textTertiary).padding(.vertical, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                ModelRow(cli: cli, item: item, measure: board.measure, scale: scale, lead: index == 0,
                         isOn: model.pick == .model(cli.engine, item.name)) {
                    model.toggle(.model(cli.engine, item.name))
                }
            }
            if list.count > Self.shown {
                Button(open ? "Show less" : "\(list.count - Self.shown) more") { model.toggleUnfolded(cli.rawValue) }
                    .buttonStyle(.reins(.normal))
                    .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ModelRow: View {
    let cli: CLIKind
    let item: TokenRanked
    let measure: TokenMeasure
    let scale: Double
    let lead: Bool
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let share = CGFloat(min(max(item.tally.value(measure) / scale, 0.01), 1))
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                if let mark = ProviderMarkKind.model(item.name, cli: cli) { ProviderMark(mark, size: lead ? 20 : 13) }
                Text(item.name).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                TokensValue(tally: item.tally, measure: measure, font: lead ? ReinsFont.rowLeader : ReinsFont.compact)
            }
            .font(lead ? ReinsFont.bodyStrong : ReinsFont.compact)
            .foregroundStyle(lead ? Palette.text : Palette.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: lead ? 46 : 26)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        shape.fill(isOn ? Palette.selection : hovering ? Palette.hover : Palette.track.opacity(0.45))
                        if item.tally.value(measure) > 0 {
                            Rectangle().fill(cli.fill.opacity(0.13)).frame(width: proxy.size.width * share)
                            Rectangle().fill(cli.fill).frame(width: proxy.size.width * share, height: 2)
                        }
                    }
                }
                .clipShape(shape)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(.bottom, lead ? 4 : 2)
        .focused($focused)
        .focusEffectDisabled()
        .focusRing(focused, cornerRadius: 6)
        .onHover { hovering = $0 }
        .help(TokensFormat.kindsTip(item.tally))
        .accessibilityLabel("\(item.name), \(TokensFormat.value(item.tally, measure))")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isOn ? "Clears this model from the scope" : "Scopes the board to this model")
    }
}

/// Projects: mirrored bars with the name in the middle and a number column on each outer edge. A row picks its project.
struct TokensProjectsCard: View {
    let model: TokensModel
    let board: TokensBoard

    static let shown = 7

    var body: some View {
        let rows = board.projects
        let open = model.unfolded.contains("projects")
        let visible = open ? rows : Array(rows.prefix(Self.shown))
        let scale = board.scale(rows.flatMap { [$0.claude, $0.codex] })
        TokensCard {
            TokensCardTitle("Projects") {
                Text("\(rows.count)")
                Spacer(minLength: 0)
                ForEach(CLIKind.allCases) { cli in
                    let unnamed = board.unnamedPercent(cli)
                    if unnamed > 0 {
                        Tag("\(cli == .claude ? "Claude" : "Codex") \(unnamed)% unnamed", tone: .warn)
                            .help("\(cli.label) tokens whose log carried no project name")
                    }
                }
            }
            if visible.isEmpty {
                Text("No project data for this scope.").font(ReinsFont.small).foregroundStyle(Palette.textTertiary).padding(10)
            }
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                ProjectRow(row: row, measure: board.measure, scale: scale, lead: index == 0, isOn: model.pick == .project(row.name)) {
                    model.toggle(.project(row.name))
                }
            }
            if rows.count > Self.shown {
                Button(open ? "Show less" : "\(rows.count - Self.shown) more") { model.toggleUnfolded("projects") }
                    .buttonStyle(.reins(.normal))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
    }
}

private struct ProjectRow: View {
    let row: TokenProjectRow
    let measure: TokenMeasure
    let scale: Double
    let lead: Bool
    let isOn: Bool
    let action: () -> Void

    static let valueWidth: CGFloat = 60
    static let nameWidth: CGFloat = 118

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                value(row.claude).frame(width: Self.valueWidth, alignment: .leading)
                TokenBar(cli: .claude, tally: row.claude, scale: scale, measure: measure, height: lead ? 9 : 5, track: false, flip: true)
                Text(row.name)
                    .font(lead ? ReinsFont.bodyStrong : ReinsFont.compact)
                    .foregroundStyle(lead ? Palette.text : Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: Self.nameWidth)
                TokenBar(cli: .codex, tally: row.codex, scale: scale, measure: measure, height: lead ? 9 : 5, track: false)
                value(row.codex).frame(width: Self.valueWidth, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: lead ? 38 : 24)
            .background(shape.fill(isOn ? Palette.selection : hovering ? Palette.hover : .clear))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .focusRing(focused, cornerRadius: 6)
        .onHover { hovering = $0 }
        .help("\(row.name)\nClaude Code \(TokensFormat.value(row.claude, measure))\nCodex \(TokensFormat.value(row.codex, measure))")
        .accessibilityLabel("\(row.name), Claude Code \(TokensFormat.value(row.claude, measure)), Codex \(TokensFormat.value(row.codex, measure))")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isOn ? "Clears this project from the scope" : "Scopes the board to this project")
    }

    @ViewBuilder
    private func value(_ tally: TokenTally) -> some View {
        if tally.isEmpty {
            Text("–").font(ReinsFont.compact).foregroundStyle(Palette.textTertiary)
        } else {
            TokensValue(tally: tally, measure: measure, font: lead ? ReinsFont.rowLeader : ReinsFont.compact)
        }
    }
}
