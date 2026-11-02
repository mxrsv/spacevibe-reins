import Foundation

// What the Tokens tab asks of the ledger: series by day, week and month, rankings of models and projects, the four
// kinds per CLI and the estimated cost, for any scope of a period bucket, a model or a project. Cost comes from
// `Pricing`; a model with no price adds tokens to `unpriced` and nothing to `cost`, never a 0.

public enum TokenPeriod: String, CaseIterable, Sendable {
    case day, week, month

    /// How many buckets a series has; nil for months, which reach back to the first counted day.
    public var bucketCount: Int? {
        switch self {
        case .day: return 30
        case .week: return 12
        case .month: return nil
        }
    }
}

public enum TokenMeasure: String, CaseIterable, Sendable {
    /// All four kinds.
    case tokens
    /// Input, cache writes and output: everything but cache reads.
    case fresh
    /// Estimated USD of the priced models.
    case cost
}

/// A model of one CLI, or a project of both.
public enum TokenPick: Hashable, Sendable {
    case model(InventoryCLI, String)
    case project(String)
}

/// Tokens and their estimate for one scope.
public struct TokenTally: Equatable, Sendable {
    public var counts = TokenCounts.zero
    /// USD for the tokens on priced models; nil when none of the tokens has a price, so "no price" never reads as $0.
    public var cost: Double?
    /// Tokens on models with no price, left out of `cost`.
    public var unpriced = 0

    public init(counts: TokenCounts = .zero, cost: Double? = nil, unpriced: Int = 0) {
        self.counts = counts; self.cost = cost; self.unpriced = unpriced
    }

    public static let empty = TokenTally()

    public var isEmpty: Bool { counts.isEmpty }

    mutating func add(_ fact: TokenFact) {
        counts += fact.counts
        if let usd = fact.cost { cost = (cost ?? 0) + usd } else { unpriced += fact.counts.total }
    }

    public static func + (a: TokenTally, b: TokenTally) -> TokenTally {
        let cost: Double? = a.cost == nil && b.cost == nil ? nil : (a.cost ?? 0) + (b.cost ?? 0)
        return TokenTally(counts: a.counts + b.counts, cost: cost, unpriced: a.unpriced + b.unpriced)
    }

    /// The number a measure ranks and draws by. A tally with no price is 0 for `cost`.
    public func value(_ measure: TokenMeasure) -> Double {
        switch measure {
        case .tokens: return Double(counts.total)
        case .fresh: return Double(counts.fresh)
        case .cost: return cost ?? 0
        }
    }

    /// Share of all tokens that were cache reads, 0 to 1; nil with no tokens.
    public var cacheShare: Double? { counts.total > 0 ? Double(counts.cacheRead) / Double(counts.total) : nil }
}

/// One bucket of a series (a day, a week or a month) with both CLIs.
public struct TokenBucket: Identifiable, Equatable, Sendable {
    public var start: LocalDay
    /// Last day, never after today.
    public var end: LocalDay
    public var claude: TokenTally
    public var codex: TokenTally

    public var id: Int { start.ordinal }
    public var range: ClosedRange<LocalDay> { start...end }
    public var both: TokenTally { claude + codex }
    public subscript(cli: InventoryCLI) -> TokenTally { cli == .claude ? claude : codex }
}

public struct TokenRanked: Identifiable, Equatable, Sendable {
    public var name: String
    public var tally: TokenTally
    public var id: String { name }
}

public struct TokenProjectRow: Identifiable, Equatable, Sendable {
    public var name: String
    public var claude: TokenTally
    public var codex: TokenTally
    public var id: String { name }
    public subscript(cli: InventoryCLI) -> TokenTally { cli == .claude ? claude : codex }
}

public struct TokenQuery: Sendable {
    public let facts: TokenFacts
    public let today: LocalDay

    public init(facts: TokenFacts, today: LocalDay) {
        self.facts = facts
        self.today = today
    }

    public init(ledger: TokenLedger, now: Date, timeZone: TimeZone, prices: [String: ModelPrice] = Pricing.models) {
        self.init(facts: TokenFacts(ledger: ledger, timeZone: timeZone, prices: prices), today: LocalDay(now, in: timeZone))
    }

    /// The bucket that holds `day`: the day itself, its Monday-to-Sunday week, or its month.
    public func bucketStart(_ period: TokenPeriod, of day: LocalDay) -> LocalDay {
        switch period {
        case .day: return day
        case .week: return day.monday
        case .month: return day.firstOfMonth
        }
    }

    private func bucketEnd(_ period: TokenPeriod, start: LocalDay) -> LocalDay {
        let end: LocalDay
        switch period {
        case .day: end = start
        case .week: end = start.adding(6)
        case .month: end = start.lastOfMonth
        }
        return min(end, today)
    }

    /// Starts of a period's buckets, newest first: the last 30 days, the last 12 weeks, or every month from the first
    /// counted day (the current month alone when nothing is counted). Today's bucket is always the first.
    public func bucketStarts(_ period: TokenPeriod) -> [LocalDay] {
        let current = bucketStart(period, of: today)
        switch period {
        case .day: return (0..<30).map { current.adding(-$0) }
        case .week: return (0..<12).map { current.adding(-7 * $0) }
        case .month:
            let first = bucketStart(.month, of: min(facts.firstDay ?? today, today))
            var out: [LocalDay] = []
            var start = current
            while start >= first {
                out.append(start)
                start = start.adding(-1).firstOfMonth
            }
            return out
        }
    }

    /// Every day a period's series covers: what the summary reads, whatever is scoped.
    public func span(_ period: TokenPeriod) -> ClosedRange<LocalDay> {
        let starts = bucketStarts(period)
        return (starts.last ?? today)...today
    }

    /// The buckets of a period, newest first, each narrowed to `pick`.
    public func buckets(_ period: TokenPeriod, pick: TokenPick? = nil) -> [TokenBucket] {
        bucketStarts(period).map { start in
            let range = start...bucketEnd(period, start: start)
            return TokenBucket(start: start, end: range.upperBound, claude: tally(.claude, in: range, pick: pick), codex: tally(.codex, in: range, pick: pick))
        }
    }

    /// Tokens of `cli` on the days in `range`. A model pick of the other CLI leaves this one empty.
    public func tally(_ cli: InventoryCLI, in range: ClosedRange<LocalDay>, pick: TokenPick? = nil) -> TokenTally {
        var out = TokenTally()
        for fact in facts.facts(in: range) where fact.cli == cli && Self.matches(fact, pick) { out.add(fact) }
        return out
    }

    private static func matches(_ fact: TokenFact, _ pick: TokenPick?) -> Bool {
        switch pick {
        case nil: return true
        case .model(let cli, let name): return fact.cli == cli && fact.model == name
        case .project(let name): return fact.project == name
        }
    }

    /// Models of `cli` with tokens in `range`, largest first by `measure`, then by tokens, then by name.
    public func models(_ cli: InventoryCLI, in range: ClosedRange<LocalDay>, by measure: TokenMeasure) -> [TokenRanked] {
        var byName: [String: TokenTally] = [:]
        for fact in facts.facts(in: range) where fact.cli == cli { byName[fact.model, default: TokenTally()].add(fact) }
        return byName.map { TokenRanked(name: $0.key, tally: $0.value) }.sorted { Self.ranks($0.tally, $0.name, before: $1.tally, $1.name, measure) }
    }

    /// Named projects with tokens in `range`, largest first by the sum of both CLIs. Tokens whose log named no project
    /// are not a row; `unnamedShare` reports them.
    public func projects(in range: ClosedRange<LocalDay>, by measure: TokenMeasure) -> [TokenProjectRow] {
        var byName: [String: (claude: TokenTally, codex: TokenTally)] = [:]
        for fact in facts.facts(in: range) {
            guard let name = fact.project else { continue }
            var pair = byName[name] ?? (TokenTally(), TokenTally())
            if fact.cli == .claude { pair.claude.add(fact) } else { pair.codex.add(fact) }
            byName[name] = pair
        }
        return byName.map { TokenProjectRow(name: $0.key, claude: $0.value.claude, codex: $0.value.codex) }
            .sorted { Self.ranks($0.claude + $0.codex, $0.name, before: $1.claude + $1.codex, $1.name, measure) }
    }

    private static func ranks(_ a: TokenTally, _ an: String, before b: TokenTally, _ bn: String, _ measure: TokenMeasure) -> Bool {
        let (va, vb) = (a.value(measure), b.value(measure))
        if va != vb { return va > vb }
        if a.counts.total != b.counts.total { return a.counts.total > b.counts.total }
        return an < bn
    }

    /// Share of the tokens of `cli` in `range` whose log named no project, 0 to 1.
    public func unnamedShare(_ cli: InventoryCLI, in range: ClosedRange<LocalDay>) -> Double {
        var all = 0
        var unnamed = 0
        for fact in facts.facts(in: range) where fact.cli == cli {
            all += fact.counts.total
            if fact.project == nil { unnamed += fact.counts.total }
        }
        return all > 0 ? Double(unnamed) / Double(all) : 0
    }

    /// Models with tokens in `range` and no price, sorted by name.
    public func unpricedModels(in range: ClosedRange<LocalDay>) -> [String] {
        Array(Set(facts.facts(in: range).filter { $0.cost == nil && !$0.counts.isEmpty }.map(\.model))).sorted()
    }

    public func sessions(_ cli: InventoryCLI, in range: ClosedRange<LocalDay>) -> Int { facts.sessions(cli, in: range) }

    /// The local day counting starts from for `cli`: its first day in the ledger; nil before anything is counted.
    public func firstDay(_ cli: InventoryCLI) -> LocalDay? { facts.firstDay(cli) }
}
