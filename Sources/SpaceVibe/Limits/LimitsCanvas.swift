import AppKit
import SwiftUI

/// The v5 Limits page (V5-R73, V5-R74; the `b-limits` mock), registered by `TabRegistry` with the v5 switch on. It reads the
/// one `LimitsModel`, whose loop the sidebar runs (`AppSidebar`): the page starts no second loop, and Refresh is one read.
@MainActor
final class LimitsTab: SpaceVibeTab {
    let id = TabRegistry.limitsID
    let title = "Limits"
    let glyph: any GlyphSource = ContentGlyph.gauge
    /// Claude Code's reading is its usage cache or status line record, Codex's its session log: files, not only logs.
    var source: String? { "Read from local files" }
    /// Only the keys the page wires (`LimitsCanvas.keys`).
    var hints: [KeyHint] {
        [KeyHint(keys: LimitsCanvas.refreshCap, label: "refresh"), KeyHint(keys: "C", label: "copy /usage"),
         KeyHint(keys: "U", label: "unused windows"), KeyHint(keys: "J K", label: "move")]
    }

    var content: AnyView { AnyView(LimitsCanvas()) }

    /// The helper inside the app bundle, which the copied commands name.
    private let helper: URL
    private let pasteboard: NSPasteboard

    init(helper: URL = CoreEnvironment.binaryURL(), pasteboard: NSPasteboard = .general) {
        self.helper = helper
        self.pasteboard = pasteboard
    }

    /// Copy only, never run (S-R4): the user pastes the line into a terminal to turn Claude limit capture on or off.
    var paletteActions: [PaletteEntry] {
        [(id: "limits.captureInstall", title: "Copy the status-line capture install command", subcommand: "install"),
         (id: "limits.captureUninstall", title: "Copy the status-line capture uninstall command", subcommand: "uninstall")]
            .map { action in
                PaletteEntry(id: action.id, title: action.title, glyph: ContentGlyph.copy, keywords: ["claude", "limits", "terminal", "setup", "remove"]) { [helper, pasteboard] in
                    pasteboard.clearContents()
                    pasteboard.setString(Self.captureCommand(helper: helper, subcommand: action.subcommand), forType: .string)
                }
            }
    }

    /// `'<helper>' statusline <subcommand>`: the path is one POSIX shell word, so a bundle in a folder with a space or a quote
    /// pastes as written.
    static func captureCommand(helper: URL, subcommand: String) -> String {
        "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "' statusline " + subcommand
    }
}

/// The Limits page's name for the shared current-row logic (V5-R36 `j`/`k`).
typealias LimitsCurrentRow = CurrentRow

/// The tab head with `Refresh`, and the split canvas: Answer, Next resets and Source on the left, Usage windows on the right,
/// one band per CLI. Every sentence, figure and state comes from `LimitsAnswer`.
struct LimitsCanvas: View {
    static let page = "limits"
    static let refreshCap = "\u{2318}R"

    @Environment(LimitsModel.self) private var model
    @Environment(ShellModel.self) private var shell
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openStateStore) private var store
    @State private var picked: String?

    var body: some View {
        // Every minute from the moment the page draws (not from the start of the minute), so an age reads as the files say.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let facts = LimitsAnswer(model.read, showUnused: model.showInactive, now: context.date)
            let rows = listedRows(facts)
            ZStack(alignment: .topLeading) {
                // Plain keys, not while the palette's field takes them (V5-R36).
                if !shell.isPaletteOpen { keys(rows) }
                VStack(spacing: 0) {
                    TabHead {
                    } actions: {
                        ToolbarButton("Refresh", keyCap: Self.refreshCap, action: refresh)
                    }
                    SplitCanvas {
                        answerCard(facts)
                        resetsCard(facts)
                        sourceCard(facts)
                    } spine: {
                        windowsCard(facts, current: LimitsCurrentRow.resolve(picked, in: rows))
                    }
                }
            }
        }
    }

    // MARK: Cards

    private func answerCard(_ facts: LimitsAnswer) -> some View {
        AnswerCard(
            sentence: facts.sentence,
            verdict: facts.verdict.map { VerdictBox(glyph: $0.glyph, glyphLabel: "Advice", title: $0.title, text: $0.text, small: $0.small) },
            isOpen: open("answer")
        ) {
            EmptyView()
        } headerActions: {
            Button(action: copyUsage) { ActionLabel("Copy /usage", key: "C") }
                .buttonStyle(ActionButtonStyle(size: .compact))
        }
    }

    private func resetsCard(_ facts: LimitsAnswer) -> some View {
        let resets = facts.resets
        let count = resets.flatMap { $0.isEmpty ? nil : "\($0.count) \($0.count == 1 ? "window" : "windows")" }
        return Tile("Next resets", count: count, layout: resets?.isEmpty == false ? .rows : .bare,
                    maxHeight: Metrics.Tile.limitsSmallMaxHeight, isOpen: open("resets")) {
            if let resets {
                if resets.isEmpty {
                    QuietEmptyState("Nothing to reset", message: "No window has a known reset time.", placement: .card)
                } else {
                    ListRows {
                        ForEach(resets) { reset in
                            ListRow(reset.title) {
                                MetaCell(text: reset.time, width: Metrics.Limits.resetTime, alignment: .leading)
                                CLIMark(reset.cli, size: .control)
                            } trailing: {
                                WarningSlot()
                            }
                        }
                    }
                }
            } else {
                LoadingSkeleton()
            }
        }
    }

    private func sourceCard(_ facts: LimitsAnswer) -> some View {
        Tile("Source", layout: .content, maxHeight: Metrics.Tile.limitsSmallMaxHeight, isOpen: open("source")) {
            VStack(alignment: .leading, spacing: Metrics.Limits.sourceLineSpacing) {
                ForEach(facts.sources) { line in
                    (Text("\(line.name) ").spaceVibeText(.metaLine, tone: .tertiary) + Text(line.state).spaceVibeText(.metaLine, tone: .secondary))
                        .lineBox(.metaLine)
                }
            }
            HStack(spacing: Metrics.Limits.sourceActionSpacing) {
                Button(action: refresh) { ActionLabel("Refresh", key: Self.refreshCap) }
                Button(action: toggleUnused) { ActionLabel(model.showInactive ? "Hide unused" : "Show unused", key: "U") }
            }
            .buttonStyle(ActionButtonStyle())
            Text("Current snapshot only. No history.").spaceVibeText(.metaLine, tone: .tertiary).lineBox(.metaLine)
        }
    }

    private func windowsCard(_ facts: LimitsAnswer, current: String?) -> some View {
        Tile("Usage windows", maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, isOpen: open("windows")) {
            BandStack {
                ForEach(facts.bands) { band in
                    Band(LimitsWording.cliName(band.cli), count: band.count, state: band.mark.map(stateMark), isOpen: open("band:\(band.id)")) {
                        bandBody(band, current: current)
                    } lead: {
                        CLIMark(band.cli, size: .control)
                    } extras: {
                        if let age = band.staleAge { StaleNote(age) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bandBody(_ band: LimitsAnswer.Band, current: String?) -> some View {
        switch band.body {
        case .loading:
            LoadingSkeleton()
        case .note(let text, let action):
            ListRows {
                ListRow(text) {
                    if let action {
                        Button { perform(action) } label: { ActionLabel(title(action), key: keyCap(action)) }
                            .buttonStyle(ActionButtonStyle())
                    }
                }
            }
        case .windows(let rows):
            ListRows {
                ForEach(rows) { row in
                    ListRow(row.name, nameWidth: Metrics.Limits.windowName, isCurrent: row.id == current,
                            onActivate: { picked = row.id }, accessibilityName: row.spoken) {
                        BarCell(share: row.left.map { Double($0) / 100 }, tone: barTone(row.tone))
                            .frame(minWidth: Metrics.Limits.barMinWidth)
                        ShareCell(percent: row.left)
                        warningSlot(row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func warningSlot(_ row: LimitsAnswer.WindowRow) -> some View {
        if let warning = row.warning {
            WarningSlot(mark: stateMark(warning.mark), detail: warning.sentence, id: "\(Self.page):\(row.id)") {
                PopoverHead(name: row.title) { CLIMark(row.cli, size: .logo) }
                PopoverSentence(warning.sentence)
                if let action = warning.action {
                    PopoverActions {
                        Button { perform(action) } label: { ActionLabel(title(action), key: keyCap(action)) }
                    }
                }
            }
        } else {
            WarningSlot()
        }
    }

    // MARK: Keys and actions

    /// `⌘R` refresh, `c` copy `/usage`, `u` unused windows, `j`/`k` and the arrows move the current row (V5-R36).
    private func keys(_ rows: [String]) -> some View {
        Group {
            HiddenKey(KeyboardShortcut("r", modifiers: .command), action: refresh)
            HiddenKey(KeyboardShortcut("c", modifiers: []), action: copyUsage)
            HiddenKey(KeyboardShortcut("u", modifiers: []), action: toggleUnused)
            HiddenKey(KeyboardShortcut("j", modifiers: [])) { picked = LimitsCurrentRow.step(picked, by: 1, in: rows) }
            HiddenKey(KeyboardShortcut(.downArrow, modifiers: [])) { picked = LimitsCurrentRow.step(picked, by: 1, in: rows) }
            HiddenKey(KeyboardShortcut("k", modifiers: [])) { picked = LimitsCurrentRow.step(picked, by: -1, in: rows) }
            HiddenKey(KeyboardShortcut(.upArrow, modifiers: [])) { picked = LimitsCurrentRow.step(picked, by: -1, in: rows) }
        }
    }

    /// Window rows the user can see: in an open band of the open Usage windows card, in page order.
    private func listedRows(_ facts: LimitsAnswer) -> [String] {
        guard store.isOpen(page: Self.page, id: "windows", byDefault: true) else { return [] }
        return facts.bands.flatMap { band -> [String] in
            guard store.isOpen(page: Self.page, id: "band:\(band.id)", byDefault: true), case .windows(let rows) = band.body else { return [] }
            return rows.map(\.id)
        }
    }

    private func refresh() {
        Task {
            let before = model.readAt
            await model.readOnce()
            if let failure = model.failure {
                toasts.show(failure, tone: .danger)
            } else if model.readAt != before {
                toasts.show("Read just now")
            }
        }
    }

    private func copyUsage() {
        LimitsClipboard.copyUsageCommand()
        toasts.show("Copied /usage. Paste it in Claude Code for exact numbers.")
    }

    private func toggleUnused() {
        model.showInactive.toggle()
        toasts.show(model.showInactive ? "Showing windows not in use" : "Hiding windows not in use")
    }

    private func perform(_ action: LimitsAnswer.Action) {
        switch action {
        case .refresh, .readNow, .retry: refresh()
        case .copyUsage: copyUsage()
        }
    }

    private func title(_ action: LimitsAnswer.Action) -> String {
        switch action {
        case .refresh: "Refresh"
        case .readNow: "Read now"
        case .retry: "Retry"
        case .copyUsage: "Copy /usage"
        }
    }

    private func keyCap(_ action: LimitsAnswer.Action) -> String {
        action == .copyUsage ? "C" : Self.refreshCap
    }

    // MARK: Mapping to blocks

    /// Every card and band starts open, as the frozen mock draws Limits (the lead's decision of 2026-11-08; V5-R55's rule is
    /// for the list pages). `OpenStateStore` keeps the user's choice.
    private func open(_ id: String) -> Binding<Bool> {
        store.binding(page: Self.page, id: id, byDefault: true)
    }

    private func stateMark(_ mark: LimitsAnswer.Mark) -> StateMark {
        switch mark.kind {
        case .warn: StateMark(.warn, label: mark.label)
        case .danger: StateMark(.danger, label: mark.label)
        case .clock: StateMark(.clock, label: mark.label)
        }
    }

    private func barTone(_ tone: LimitsWording.Tone) -> BarTone {
        switch tone {
        case .normal: .neutral
        case .low: .warn
        case .out: .danger
        }
    }
}
