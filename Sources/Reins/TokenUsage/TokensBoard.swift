import Foundation
import ReinsCore

/// Everything one frame of the Tokens board shows, computed from the query and the model's choices. The summary always
/// covers the whole period; every other card reads the scope: the picked bucket (else the whole period) narrowed to the
/// picked model or project.
struct TokensBoard {
    let query: TokenQuery
    let period: TokenPeriod
    let measure: TokenMeasure
    let pick: TokenPick?
    /// Newest first, each narrowed to the pick.
    let buckets: [TokenBucket]
    let selected: TokenBucket?
    let span: ClosedRange<LocalDay>

    init(query: TokenQuery, period: TokenPeriod, measure: TokenMeasure, selectedID: Int?, pick: TokenPick?) {
        self.query = query
        self.period = period
        self.measure = measure
        self.pick = pick
        let all = query.buckets(period, pick: pick)
        buckets = all
        selected = selectedID.flatMap { id in all.first { $0.id == id } }
        span = query.span(period)
    }

    var timeZone: TimeZone { query.facts.timeZone }
    var today: LocalDay { query.today }
    /// The days every card but the summary reads.
    var scope: ClosedRange<LocalDay> { selected?.range ?? span }

    func label(_ bucket: TokenBucket) -> String {
        TokensFormat.bucketLabel(bucket, period: period, today: today, timeZone: timeZone)
    }

    // MARK: Summary (whole period, no pick)

    func summary(_ cli: CLIKind) -> TokenTally { query.tally(cli.engine, in: span) }
    var summaryBoth: TokenTally { summary(.claude) + summary(.codex) }
    func sessions(_ cli: CLIKind) -> Int { query.sessions(cli.engine, in: span) }

    // MARK: Scoped cards

    func scoped(_ cli: CLIKind) -> TokenTally { query.tally(cli.engine, in: scope, pick: pick) }
    func models(_ cli: CLIKind) -> [TokenRanked] { query.models(cli.engine, in: scope, by: measure) }
    var projects: [TokenProjectRow] { query.projects(in: scope, by: measure) }
    /// Whole percent of a CLI's tokens in scope whose log named no project.
    func unnamedPercent(_ cli: CLIKind) -> Int { Int((query.unnamedShare(cli.engine, in: scope) * 100).rounded()) }
    var unpricedModels: [String] { query.unpricedModels(in: scope) }

    var scopeIsEmpty: Bool { scoped(.claude).isEmpty && scoped(.codex).isEmpty }

    // MARK: By day

    /// The y axis of the series and how many buckets rise above it. One bucket far above the rest is cut so the others
    /// stay readable: the axis stops at a round number near twice the second largest value, and the cut bucket prints
    /// its value.
    struct Axis: Equatable {
        var top: Double
        var cut: Int
    }

    var axis: Axis {
        let values = buckets.flatMap { [$0.claude.value(measure), $0.codex.value(measure)] }.sorted(by: >)
        let first = values.first ?? 0
        let second = values.count > 1 && values[1] > 0 ? values[1] : (first > 0 ? first : 1)
        let cap = Self.nice(2 * second)
        let top = first > cap ? cap : Self.nice(first > 0 ? first : 1)
        let cut = buckets.filter { max($0.claude.value(measure), $0.codex.value(measure)) > top }.count
        return Axis(top: top, cut: cut)
    }

    /// 1, 2 or 5 times a power of ten, at or above `value`.
    static func nice(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let power = pow(10, (log10(value)).rounded(.down))
        let fraction = value / power
        let step: Double = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10
        return step * power
    }

    /// The bucket with the most of both CLIs together; nil when every bucket is empty.
    var peak: TokenBucket? {
        buckets.filter { !$0.both.isEmpty }.max { $0.both.value(measure) < $1.both.value(measure) }
    }

    /// Bars of one series, oldest first, as the By day card draws them left to right.
    var columns: [TokenBucket] { buckets.reversed() }

    /// The largest single-CLI value in a list of tallies, at least 1, for scaling bars.
    func scale(_ tallies: [TokenTally]) -> Double { max(tallies.map { $0.value(measure) }.max() ?? 0, 1) }
}
