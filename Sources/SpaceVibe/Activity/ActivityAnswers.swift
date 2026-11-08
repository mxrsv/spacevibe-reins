import Foundation

/// One tab's Answer card (V5-R53): the sentence, an optional verdict box naming the first row that needs the user, and how many
/// more rows are marked in the list. Derived from the query in one function per tab, never a fixed string.
struct ActivityAnswer: Equatable, Sendable {
    struct Verdict: Equatable, Sendable {
        /// The row the fix acts on: a session id, a failure id or a file path, as `ActivityQuery` names them.
        let targetID: String
        let title: String
        let text: String
        let small: String?
    }

    /// Nil while the report has not arrived: the card shows its skeleton.
    let sentence: String?
    let verdict: Verdict?
    /// Rows beyond the one named: "N more are marked in the list."
    let more: Int

    static let loading = ActivityAnswer(sentence: nil, verdict: nil, more: 0)

    private init(sentence: String?, verdict: Verdict?, more: Int) {
        self.sentence = sentence
        self.verdict = verdict
        self.more = more
    }

    // MARK: Running (V5-R70)

    /// "N waiting for you", or that nothing is. A session whose state the core cannot tell (a long tool run looks the same as an
    /// approval wait, and neither CLI logs the approval) means "nothing" is not known, so the sentence says that instead.
    static func running(_ query: ActivityQuery) -> ActivityAnswer {
        guard !query.isLoading else { return .loading }
        if query.pickedAreAllMissing {
            let names = ActivityFilterField.cli.values.filter { query.filter.isPicked(.cli, $0.id) }.map(\.title)
            return ActivityAnswer(sentence: "\(names.joined(separator: " and ")) \(names.count == 1 ? "is" : "are") not installed.", verdict: nil, more: 0)
        }
        let waiting = query.sessions.filter(\.isWaiting)
        if let first = waiting.first {
            let session = first.session
            let place = session.project.map { "In \($0). " } ?? ""
            return ActivityAnswer(
                sentence: "\(waiting.count) waiting for you\(query.scope)",
                verdict: Verdict(targetID: first.id, title: session.title, text: "\(session.cli.label) is waiting for your answer to a question.",
                                 small: "\(place)Answer it in the terminal. The log does not hold the question."),
                more: waiting.count - 1)
        }
        let unread = query.sessions.filter(\.isUnmeasurable)
        guard let first = unread.first else {
            return ActivityAnswer(sentence: "Nothing\(query.scope) is waiting for you.", verdict: nil, more: 0)
        }
        let count = unread.count, open = query.sessions.count
        return ActivityAnswer(
            sentence: "Nothing\(query.scope) is known to be waiting for you.",
            verdict: Verdict(targetID: first.id, title: first.session.title, text: first.session.stateReason,
                             small: "\(count) of \(open) open \(open == 1 ? "session" : "sessions") cannot be measured."),
            more: count - 1)
    }

    // MARK: Failed (V5-R71)

    static func failed(_ query: ActivityQuery) -> ActivityAnswer {
        guard !query.isLoading else { return .loading }
        let still = query.failures.filter(\.stillFailing)
        guard let first = still.first else {
            return ActivityAnswer(sentence: "No command\(query.scope) is still failing.", verdict: nil, more: 0)
        }
        return ActivityAnswer(
            sentence: "\(still.count) still failing\(query.scope)",
            verdict: Verdict(targetID: first.id, title: first.failure.title, text: first.failure.reason,
                             small: "\(first.failure.cli.label). No later run has passed."),
            more: still.count - 1)
    }

    // MARK: Files (V5-R72)

    /// The core reports each file's edits over the logs it read, and one last-edit time; "today's most-edited file" needs the
    /// edits of today, which it does not report (G14), so this names the most-edited file of the logs read.
    static func files(_ query: ActivityQuery) -> ActivityAnswer {
        guard !query.isLoading else { return .loading }
        guard let top = query.files.first else {
            return ActivityAnswer(sentence: "No file edits are in the session logs.", verdict: nil, more: 0)
        }
        let file = top.file
        return ActivityAnswer(
            sentence: "\(top.name) is the most-edited file.",
            verdict: Verdict(targetID: top.id, title: "Edited \(file.edits == 1 ? "once" : "\(file.edits) times")",
                             text: "Across \(ActivityFormat.plural(file.sessions, "session")), last edit \(ActivityFormat.ago(file.last, now: query.now)).",
                             small: file.path),
            more: 0)
    }
}

/// The figures and labels of the cards beside the Answers.
enum ActivityFigures {
    /// The `Right now` card (V5-R70's `Today`): what the report holds about the sessions open now. It has no tool-call count and
    /// no cost per day (G4), and its cost is per session over its whole life, so nothing here is called "today". Empty when
    /// no session is open, which drops the card.
    static func rightNow(_ query: ActivityQuery) -> [StatFigures.Figure] {
        let open = query.sessions
        guard !open.isEmpty else { return [] }
        var figures: [StatFigures.Figure] = []
        let costs = open.compactMap { $0.session.cost?.usd }
        if !costs.isEmpty {
            let covers = costs.count == open.count ? "open sessions" : "\(costs.count) of \(open.count) open sessions"
            figures.append(.init(value: ActivityFormat.cost(costs.reduce(0, +)), label: "estimated cost, \(covers)"))
        }
        if let oldest = open.compactMap({ $0.session.ageMs }).max() {
            figures.append(.init(value: ActivityFormat.span(oldest + query.elapsedMs), label: "longest-open session"))
        }
        return figures
    }

    // MARK: Failed

    /// "Oct 25 to Nov 7": the span of the failures listed, from the core's first and last times (the core reports no scan window).
    /// Nil when none has a time.
    static func failedRange(_ failures: [ActivityFailureItem], calendar: Calendar = .current) -> String? {
        let first = failures.compactMap { ActivityFormat.date($0.failure.first) }.min()
        let last = failures.compactMap { ActivityFormat.date($0.failure.last) }.max()
        guard let first, let last else { return nil }
        let from = ActivityFormat.shortDay(first, calendar: calendar), to = ActivityFormat.shortDay(last, calendar: calendar)
        return from == to ? from : "\(from) to \(to)"
    }

    /// The Failed spine's count: "5 commands, Oct 25 to Nov 7".
    static func failedCount(_ query: ActivityQuery, calendar: Calendar = .current) -> String {
        let n = ActivityFormat.plural(query.failures.count, "command")
        return failedRange(query.failures, calendar: calendar).map { "\(n), \($0)" } ?? n
    }

    /// The `Passed later` card: one sentence, nothing about a fix (one pass is not proof). Nil when no command passed later.
    static func passedLater(_ query: ActivityQuery) -> (count: Int, sentence: String)? {
        let passed = query.failures.filter { !$0.stillFailing }
        guard !passed.isEmpty else { return nil }
        let n = passed.count
        return (n, "\(ActivityFormat.plural(n, "command")) failed, then passed on a later run. One pass is not proof of a fix.")
    }

    /// What `Dismiss passed` says in its toast.
    static func dismissedPassedLabel(_ count: Int) -> String {
        "Dismissed \(ActivityFormat.plural(count, "command")) that passed later"
    }

    // MARK: Files

    /// One bar of `Busiest projects`: the edits of the files only that project touched. A file two projects touched cannot be
    /// split (the core reports its edits once), so it is counted nowhere and `skipped` says how many.
    struct Busiest: Equatable, Sendable {
        struct Entry: Equatable, Sendable, Identifiable {
            let name: String
            let edits: Int
            var id: String { name }
        }

        var entries: [Entry]
        var skipped: Int

        var isEmpty: Bool { entries.isEmpty }
    }

    static func busiest(_ query: ActivityQuery, limit: Int = 8) -> Busiest {
        var edits: [String: Int] = [:]
        var skipped = 0
        for item in query.files {
            if item.file.projects.count == 1, let project = item.file.projects.first {
                edits[project, default: 0] += item.file.edits
            } else if item.file.projects.count > 1 {
                skipped += 1
            }
        }
        let entries = edits.map { Busiest.Entry(name: $0.key, edits: $0.value) }
            .sorted { ($0.edits, $1.name) > ($1.edits, $0.name) }
        return Busiest(entries: Array(entries.prefix(limit)), skipped: skipped)
    }

    /// The Busiest projects card's count: what the edits were counted in. The core reports the number of logs it read, not a
    /// time range.
    static func busiestCount(_ query: ActivityQuery) -> String {
        "file edits in \(ActivityFormat.plural(query.logs, "log")) read"
    }

    static func skippedNote(_ skipped: Int) -> String? {
        skipped == 0 ? nil : "\(ActivityFormat.plural(skipped, "file")) edited in more than one project \(skipped == 1 ? "is" : "are") not counted here."
    }
}

/// The sentences of the row detail popovers (V5-R57) and the label of the file action.
enum ActivityWording {
    static let answerInTerminal = "Answer in the terminal. SpaceVibe only shows that it is waiting."
    /// `Open` on a file shows it in Finder and never opens or runs it: the path comes from a log (G11).
    static let showFile = "Show in Finder"

    static func sessionLines(_ item: ActivitySessionItem, elapsedMs: Double) -> [String] {
        let session = item.session
        var lines = [session.stateReason]
        if item.isWaiting { lines.append(answerInTerminal) }
        // A running session's log would not show an approval wait: say so in the core's words (an unmeasurable one says it above).
        if !item.isUnmeasurable, let limit = item.cannotSee { lines.append(limit) }
        if let ago = session.lastWriteAgoMs {
            lines.append("Last log write \(ActivityFormat.span(ago + elapsedMs)) ago.")
        } else if let age = session.ageMs {
            lines.append("Started \(ActivityFormat.span(age + elapsedMs)) ago.")
        }
        if let cost = session.cost {
            lines.append("\(ActivityFormat.cost(cost.usd)) so far, estimated at API prices. It is not what a subscription bills.")
        } else if let note = session.costNote {
            lines.append(note)
        }
        return lines
    }

    static func failureLines(_ item: ActivityFailureItem, now: Date) -> [String] {
        let failure = item.failure
        var lines = ["\(failure.reason). Failed \(item.timesText) in \(ActivityFormat.plural(failure.sessions, "session"))."]
        if let hook = failure.hook { lines.append("A \(hook.event) hook.") }
        if let first = failure.first, let last = failure.last {
            lines.append(failure.count > 1 ? "First \(ActivityFormat.clock(first, now: now)), last \(ActivityFormat.clock(last, now: now))."
                                           : "At \(ActivityFormat.clock(last, now: now)).")
        }
        lines.append(ActivityFormat.laterPass(failure, now: now).map { "\($0.prefix(1).uppercased())\($0.dropFirst())." } ?? "No later run has passed.")
        return lines
    }

    static func fileLines(_ item: ActivityFileItem, now: Date) -> [String] {
        let file = item.file
        var lines = ["\(item.editsText) across \(ActivityFormat.plural(file.sessions, "session")), last edit \(ActivityFormat.ago(file.last, now: now))."]
        lines.append("Edited by \(file.clis.map(\.label).joined(separator: " and ")).")
        return lines
    }
}
