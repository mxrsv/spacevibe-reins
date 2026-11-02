import ReinsCore
import SwiftUI

/// What has keyboard focus on the board: a column of By day, or a row of Days. `←` `→` move the picked bucket and the
/// focus with it.
enum TokensFocus: Hashable {
    case column(Int)
    case row(Int)
}

/// The Tokens tab: the first scan, no logs, a failed scan, or the Board (tools row and cards).
struct TokensScreen: View {
    @Bindable var model: TokensModel
    @Environment(ShellModel.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: TokensFocus?

    var body: some View {
        let isActive = shell.activeID == TokensTab.tabID
        content
            .task(id: isActive) { if isActive { await model.refreshIfStale() } }
            .onKeyPress(.leftArrow) { move(-1) }
            .onKeyPress(.rightArrow) { move(1) }
            .onKeyPress(.return) { model.openSelected() ? .handled : .ignored }
            .onKeyPress(.escape) { model.escape() ? .handled : .ignored }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.selectedID)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard let id = model.move(step) else { return .ignored }
        if case .row = focus { focus = .row(id) } else { focus = .column(id) }
        return .handled
    }

    @ViewBuilder
    private var content: some View {
        if let board = model.board, !model.hasNoLogs {
            PageLayout(
                tools: {
                    VStack(alignment: .leading, spacing: 8) {
                        TokensToolsRow(model: model, board: board)
                        notes
                    }
                },
                content: { TokensBoardView(model: model, board: board, focus: $focus).modifier(ShotFit()) }
            )
        } else if model.hasNoLogs {
            PageLayout {
                EmptyState("No session logs yet",
                           message: "Tokens are counted from Claude Code transcripts and Codex rollouts. None were found, and nothing was counted before.",
                           systemImage: "tray") {
                    Button("Scan again", action: model.rescan).buttonStyle(.reins(.normal))
                }
            }
        } else if let failure = model.failure {
            PageLayout {
                EmptyState("Could not count tokens.", message: failure, systemImage: "exclamationmark.triangle") {
                    Button("Try again", action: model.rescan).buttonStyle(.reins(.normal))
                }
            }
        } else {
            PageLayout {
                EmptyState("Counting tokens\u{2026}", message: progressText, systemImage: nil) { LoadingMark() }
            }
        }
    }

    private var progressText: String {
        let lead = "The first count of a long history can take a while. Logs are only read."
        guard let progress = model.progress, progress.total > 0 else { return lead }
        return "\(TokensFormat.count(progress.done)) of \(TokensFormat.count(progress.total)) logs. \(lead)"
    }

    @ViewBuilder
    private var notes: some View {
        if let moved = model.result?.movedAside {
            Banner(.warn, message: "The token history could not be read, so it was moved aside and counting started again from the logs present.",
                   detail: "Days whose logs are gone are missing. The old file is at \(moved).")
        }
        if let notSaved = model.result?.notSaved {
            Banner(.warn, message: "The token history was not saved.", detail: notSaved)
        }
        if let failure = model.failure {
            Banner(.error, message: "The last scan failed, so this may be out of date.", detail: failure, actionTitle: "Try again", action: model.rescan)
        }
    }
}

/// Period, measure, a chip for each active scope, and the day counting starts from for each CLI.
struct TokensToolsRow: View {
    @Bindable var model: TokensModel
    let board: TokensBoard

    var body: some View {
        HStack(spacing: 10) {
            SegmentedControl(label: "Period", options: TokenPeriod.allCases.map { SegmentOption(TokensFormat.periodTitle($0), value: $0) }, selection: $model.period)
            HStack(spacing: 6) {
                ForEach(TokenMeasure.allCases, id: \.self) { measure in
                    FilterChip(TokensFormat.measureTitle(measure), isOn: model.measure == measure) { model.measure = measure }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Measure")
            if let selected = board.selected {
                FilterChip(dismissing: board.label(selected)) { model.selectedID = nil }
            }
            if let title = model.pickTitle {
                FilterChip(dismissing: title) { model.pick = nil }
            }
            Spacer(minLength: 12)
            Text(TokensFormat.countingFrom(board.query))
                .font(ReinsFont.small)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }
}

/// The cards: summary, By day beside Cache reuse and Estimated cost, Models beside Projects, then Days.
struct TokensBoardView: View {
    let model: TokensModel
    let board: TokensBoard
    var focus: FocusState<TokensFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TokensSummaryCard(board: board)
            WeightedRow(weights: [2.15, 1]) {
                TokensTimelineCard(model: model, board: board, focus: focus)
                VStack(spacing: 12) {
                    TokensCacheCard(board: board).fixedSize(horizontal: false, vertical: true)
                    TokensCostCard(model: model, board: board)
                }
            }
            .zIndex(1)
            WeightedRow(weights: [1.2, 1]) {
                TokensModelsCard(model: model, board: board)
                TokensProjectsCard(model: model, board: board)
            }
            TokensDaysCard(model: model, board: board, focus: focus)
        }
    }
}
