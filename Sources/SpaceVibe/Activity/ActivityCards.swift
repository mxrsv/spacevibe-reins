import SwiftUI

/// The cards of the three Activity tabs (V5-R70 to V5-R72): the Answer, the small cards and the spine of each, with the row
/// detail popovers. Layout and wiring only: every sentence is `ActivityAnswers`', every list `ActivityQuery`'s.
struct ActivityCards: View {
    let pane: ActivityPane
    let model: ActivityModel
    let query: ActivityQuery
    let current: String?
    let now: Date

    @Environment(\.openStateStore) private var store
    @Environment(ShellModel.self) private var shell

    var body: some View {
        switch pane {
        case .running: running
        case .failed: failed
        case .files: files
        }
    }

    private var page: String { ActivityCanvas.page }

    private func open(_ id: String) -> Binding<Bool> { store.binding(page: page, id: id, byDefault: true) }

    private func band(_ id: String, problem: Bool, offset: Int, needs: Bool) -> Binding<Bool> {
        store.binding(page: page, id: id, byDefault: OpenStateStore.defaultOpen(holdsProblem: problem, isFirst: offset == 0, pageNeedsUser: needs))
    }
}

// MARK: Running (V5-R70)

extension ActivityCards {
    fileprivate var running: some View {
        let answer = ActivityAnswer.running(query)
        let figures = ActivityFigures.rightNow(query)
        return SplitCanvas {
            answerCard(answer, id: "running.answer", fix: runningFix(answer))
            if query.isLoading {
                Tile("Right now", layout: .bare, isOpen: open("running.now")) { LoadingSkeleton() }
            } else if !figures.isEmpty {
                Tile("Right now", layout: .content, isOpen: open("running.now")) {
                    StatFigures(figures: figures)
                    HStack {
                        Spacer(minLength: 0)
                        Button { shell.openLimits() } label: { ActionLabel("Limits", glyph: .gauge) }.buttonStyle(ActionButtonStyle())
                    }
                }
            }
        } spine: {
            Tile("Running", count: query.isLoading ? nil : ActivityFormat.plural(query.sessions.count, "session"), layout: spineLayout(empty: query.sessions.isEmpty),
                 maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, scrollTarget: current, isOpen: open("running.spine")) {
                runningSpine
            }
        }
    }

    private func spineLayout(empty: Bool) -> TileLayout { query.isLoading || empty ? .bare : .rows }

    @ViewBuilder
    private var runningSpine: some View {
        if query.isLoading {
            LoadingSkeleton()
        } else if query.sessions.isEmpty {
            QuietEmptyState(query.filter.isOn ? "No session matches the filter" : "No session is running",
                            message: query.filter.isOn ? "Clear the filter to see every CLI." : "Sessions show up here while a CLI runs.", placement: .card)
        } else {
            let needs = query.sessionBands.contains(where: \.holdsProblem)
            BandStack {
                ForEach(Array(query.sessionBands.enumerated()), id: \.element.id) { offset, item in
                    Band(item.name, count: item.items.isEmpty ? nil : item.items.count,
                         state: item.waiting > 0 ? StateMark(.warn, label: "\(item.waiting) waiting for you") : nil,
                         isOpen: band("run:\(item.id)", problem: item.holdsProblem, offset: offset, needs: needs)) {
                        sessionRows(item)
                    } lead: {
                        CLIMark(item.cli, size: .control)
                    } extras: {
                        if let extra = item.extra { Text(extra).spaceVibeText(.meta, tone: .tertiary).lineLimit(1) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRows(_ band: ActivitySessionBand) -> some View {
        ListRows {
            if let note = band.note, band.items.isEmpty {
                ListRow(note)
            }
            ForEach(band.items) { item in sessionRow(item) }
        }
    }

    private func sessionRow(_ item: ActivitySessionItem) -> some View {
        ListRow(item.session.title, isCurrent: item.id == current, onActivate: { model.open(item.id) }, accessibilityName: item.spoken) {
            MetaCell(text: item.session.project ?? "", width: Metrics.Activity.projectWidth, alignment: .leading)
            MetaCell(text: item.stateText, width: Metrics.Activity.stateWidth)
            sessionSlot(item)
        }
        .id(item.id)
        .anchoredOverlay(isPresented: model.detailID == item.id, id: "\(page):detail", placement: .popover, onOutsideTap: { model.detailID = nil }) {
            sessionDetail(item)
        }
    }

    @ViewBuilder
    private func sessionSlot(_ item: ActivitySessionItem) -> some View {
        if item.isWaiting || item.isUnmeasurable {
            let mark = item.isWaiting ? StateMark(.warn, label: "Waiting for you") : StateMark(.clock, label: "Not measurable")
            WarningSlot(mark: mark, detail: item.session.stateReason, id: "\(page):warn:\(item.id)") {
                PopoverSentence(item.session.stateReason)
                if item.isWaiting { PopoverSentence(ActivityWording.answerInTerminal) }
                if item.isWaiting, item.canStop { PopoverActions { stopButton(item, key: "S") } }
            }
        } else {
            WarningSlot()
        }
    }

    private func stopButton(_ item: ActivitySessionItem, key: String? = nil) -> some View {
        Button { model.requestStop(item.session) } label: { ActionLabel("Stop\u{2026}", glyph: .stop, key: key) }
    }

    private func sessionDetail(_ item: ActivitySessionItem) -> some View {
        let session = item.session
        return PopoverSurface(onExit: { model.detailID = nil }) {
            PopoverHead(name: session.title, sub: [session.cli.label, session.project].compactMap { $0 }.joined(separator: ", ")) {
                CLIMark(session.cli, size: .logo)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ActivityWording.sessionLines(item, elapsedMs: query.elapsedMs), id: \.self) { PopoverSentence($0) }
            }
            if item.canStop { PopoverActions { stopButton(item, key: "S") } }
        }
    }

    private func runningFix(_ answer: ActivityAnswer) -> (() -> AnyView)? {
        guard let target = answer.verdict?.targetID, let item = query.sessions.first(where: { $0.id == target }), item.isWaiting, item.canStop else { return nil }
        return { AnyView(stopButton(item)) }
    }

    // MARK: The Answer card

    @ViewBuilder
    private func answerCard(_ answer: ActivityAnswer, id: String, fix: (() -> AnyView)?) -> some View {
        let verdict = answer.verdict.map { VerdictBox(glyph: .used, glyphLabel: "Advice", title: $0.title, text: $0.text, small: $0.small) }
        if let fix {
            AnswerCard(sentence: answer.sentence, verdict: verdict, moreMarked: answer.more, isOpen: open(id)) {
                fix().buttonStyle(ActionButtonStyle())
            }
        } else {
            AnswerCard(sentence: answer.sentence, verdict: verdict, moreMarked: answer.more, isOpen: open(id))
        }
    }
}

// MARK: Failed (V5-R71)

extension ActivityCards {
    fileprivate var failed: some View {
        let answer = ActivityAnswer.failed(query)
        let passed = ActivityFigures.passedLater(query)
        return SplitCanvas {
            failedAnswer(answer)
            if query.isLoading {
                Tile("Passed later", layout: .bare, isOpen: open("failed.passed")) { LoadingSkeleton() }
            } else if let passed {
                Tile("Passed later", layout: .content, isOpen: open("failed.passed")) {
                    Text(passed.sentence).spaceVibeText(.prose, tone: .secondary).fixedSize(horizontal: false, vertical: true).lineBox(.prose)
                    Button { model.dismissPassed() } label: { ActionLabel("Dismiss passed", glyph: .close) }.buttonStyle(ActionButtonStyle())
                }
            }
        } spine: {
            Tile("Failed commands", count: query.isLoading ? nil : ActivityFigures.failedCount(query), layout: spineLayout(empty: query.failures.isEmpty),
                 maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, scrollTarget: current, isOpen: open("failed.spine")) {
                failedSpine
            }
        }
    }

    @ViewBuilder
    private func failedAnswer(_ answer: ActivityAnswer) -> some View {
        if let target = answer.verdict?.targetID, let item = query.failures.first(where: { $0.id == target }) {
            answerCard(answer, id: "failed.answer") {
                AnyView(Button { model.copy(item) } label: { ActionLabel("Copy", glyph: .copy) })
            }
        } else {
            answerCard(answer, id: "failed.answer", fix: nil)
        }
    }

    @ViewBuilder
    private var failedSpine: some View {
        if query.isLoading {
            LoadingSkeleton()
        } else if query.failures.isEmpty {
            QuietEmptyState("No failed commands", message: "No command in the session logs exited with an error.", placement: .card)
        } else {
            let needs = query.failureBands.contains(where: \.holdsProblem)
            BandStack {
                ForEach(Array(query.failureBands.enumerated()), id: \.element.id) { offset, item in
                    Band(LimitsWording.cliName(CoreLimitsCLI(item.cli)), count: item.items.count,
                         state: item.stillFailing > 0 ? StateMark(.warn, label: "\(item.stillFailing) still failing") : nil,
                         isOpen: band("fail:\(item.id)", problem: item.holdsProblem, offset: offset, needs: needs)) {
                        ListRows { ForEach(item.items) { failureRow($0) } }
                    } lead: {
                        CLIMark(item.cli, size: .control)
                    }
                }
            }
        }
    }

    private func failureRow(_ item: ActivityFailureItem) -> some View {
        ListRow(item.failure.title, isCurrent: item.id == current, onActivate: { model.open(item.id) }, accessibilityName: item.spoken) {
            MetaCell(text: item.failure.reason, alignment: .leading).frame(maxWidth: Metrics.Activity.reasonMaxWidth, alignment: .leading)
            CountCell(text: item.timesText, width: Metrics.Activity.timesWidth)
            MetaCell(text: item.statusText, width: Metrics.Activity.statusWidth)
            failureSlot(item)
        }
        .id(item.id)
        .anchoredOverlay(isPresented: model.detailID == item.id, id: "\(page):detail", placement: .popover, onOutsideTap: { model.detailID = nil }) {
            failureDetail(item)
        }
    }

    @ViewBuilder
    private func failureSlot(_ item: ActivityFailureItem) -> some View {
        if item.stillFailing {
            WarningSlot(mark: StateMark(.warn, label: "Still failing"), detail: item.failure.reason, id: "\(page):warn:\(item.id)") {
                PopoverSentence("\(item.failure.reason). No later run has passed.")
                PopoverActions { copyButton(item, key: "C") }
            }
        } else {
            WarningSlot()
        }
    }

    private func copyButton(_ item: ActivityFailureItem, key: String? = nil) -> some View {
        Button { model.copy(item) } label: { ActionLabel("Copy", key: key) }
    }

    private func failureDetail(_ item: ActivityFailureItem) -> some View {
        PopoverSurface(onExit: { model.detailID = nil }) {
            PopoverHead(name: item.failure.title, sub: item.failure.cli.label) { CLIMark(item.failure.cli, size: .logo) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ActivityWording.failureLines(item, now: query.now), id: \.self) { PopoverSentence($0) }
            }
            PopoverActions {
                copyButton(item, key: "C")
                Button { model.dismiss(item) } label: { ActionLabel("Dismiss") }
            }
        }
    }
}

// MARK: Files (V5-R72)

extension ActivityCards {
    fileprivate var files: some View {
        let answer = ActivityAnswer.files(query)
        let busiest = ActivityFigures.busiest(query)
        return SplitCanvas {
            filesAnswer(answer)
            if query.isLoading {
                Tile("Busiest projects", layout: .bare, isOpen: open("files.busiest")) { LoadingSkeleton() }
            } else if !busiest.isEmpty {
                busiestCard(busiest)
            }
        } spine: {
            Tile("Edited files", count: query.isLoading ? nil : ActivityFormat.plural(query.files.count, "file"), layout: spineLayout(empty: query.files.isEmpty),
                 maxHeight: Metrics.Tile.spineMaxHeight, stretches: true, scrollTarget: current, isOpen: open("files.spine")) {
                filesSpine
            }
        }
    }

    @ViewBuilder
    private func filesAnswer(_ answer: ActivityAnswer) -> some View {
        if let target = answer.verdict?.targetID, let item = query.files.first(where: { $0.id == target }) {
            answerCard(answer, id: "files.answer") {
                AnyView(Button { model.reveal(item) } label: { ActionLabel(ActivityWording.showFile, glyph: .open) })
            }
        } else {
            answerCard(answer, id: "files.answer", fix: nil)
        }
    }

    private func busiestCard(_ busiest: ActivityFigures.Busiest) -> some View {
        let most = Double(busiest.entries.first?.edits ?? 1)
        return Tile("Busiest projects", count: ActivityFigures.busiestCount(query), maxHeight: Metrics.Tile.limitsSmallMaxHeight, isOpen: open("files.busiest")) {
            ListRows {
                ForEach(busiest.entries) { entry in
                    ListRow(entry.name, nameWidth: Metrics.Activity.projectNameWidth) {
                        BarCell(share: Double(entry.edits) / most).frame(minWidth: Metrics.Limits.barMinWidth)
                        CountCell(text: ActivityFormat.plural(entry.edits, "edit"), width: Metrics.Activity.editsWidth)
                    }
                }
            }
            if let note = ActivityFigures.skippedNote(busiest.skipped) {
                Text(note)
                    .spaceVibeText(.metaLine, tone: .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(.metaLine)
                    .padding(.horizontal, Metrics.ListRow.leading)
                    .padding(.top, Metrics.Activity.noteTop)
            }
        }
    }

    @ViewBuilder
    private var filesSpine: some View {
        if query.isLoading {
            LoadingSkeleton()
        } else if query.files.isEmpty {
            QuietEmptyState("No files edited", message: "Files that sessions edit show up here.", placement: .card)
        } else {
            BandStack {
                ForEach(Array(query.fileBands.enumerated()), id: \.element.id) { offset, item in
                    Band(item.title, count: item.items.count, isOpen: band("files:\(item.id)", problem: false, offset: offset, needs: false)) {
                        ListRows { ForEach(item.items) { fileRow($0) } }
                    }
                }
            }
        }
    }

    private func fileRow(_ item: ActivityFileItem) -> some View {
        ListRow(item.name, isCurrent: item.id == current, onActivate: { model.open(item.id) }, accessibilityName: item.file.path) {
            MetaCell(text: item.folder).frame(maxWidth: Metrics.Activity.folderMaxWidth, alignment: .trailing)
            CountCell(text: item.editsText, width: Metrics.Activity.editsWidth)
        }
        .id(item.id)
        .anchoredOverlay(isPresented: model.detailID == item.id, id: "\(page):detail", placement: .popover, onOutsideTap: { model.detailID = nil }) {
            fileDetail(item)
        }
    }

    private func fileDetail(_ item: ActivityFileItem) -> some View {
        PopoverSurface(onExit: { model.detailID = nil }) {
            PopoverHead(name: item.name, sub: item.folder.isEmpty ? "project root" : item.folder) { SpaceVibeIcon(content: .file, size: .row, ink: TextTone.tertiary.color) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ActivityWording.fileLines(item, now: query.now), id: \.self) { PopoverSentence($0) }
                PopoverPath(item.file.path)
            }
            PopoverActions { Button { model.reveal(item) } label: { ActionLabel(ActivityWording.showFile, key: "O") } }
        }
    }
}
