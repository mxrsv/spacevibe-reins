import Foundation

// The ledger's UTC hours turned into local calendar days of one time zone, the unit every Tokens view reads.
// The ledger stores UTC hours so a time zone change cannot make it wrong; the day is computed here, when read. In a
// zone with a half-hour offset an hour is counted on the day its start falls in.

/// A calendar day, as days since 1970-01-01 in the proleptic Gregorian calendar. Pure arithmetic, so it means the
/// same on every platform and needs no `Calendar`.
public struct LocalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

    public init(year: Int, month: Int, day: Int) {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        ordinal = era * 146_097 + doe - 719_468
    }

    /// The local day `date` falls on in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone) {
        let seconds = Int(date.timeIntervalSince1970.rounded(.down)) + timeZone.secondsFromGMT(for: date)
        ordinal = Self.floorDiv(seconds, 86_400)
    }

    /// The local day a UTC hour of the ledger starts on.
    public init(utcHour hour: Int, in timeZone: TimeZone) {
        self.init(Date(timeIntervalSince1970: TimeInterval(hour) * 3600), in: timeZone)
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : (a - b + 1) / b }

    /// Year, month (1 to 12) and day (1 to 31).
    public var civil: (year: Int, month: Int, day: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    /// 1 for Monday through 7 for Sunday (ISO 8601). 1970-01-01 was a Thursday.
    public var weekday: Int { ((ordinal + 3) % 7 + 7) % 7 + 1 }
    /// The Monday that starts this day's week.
    public var monday: LocalDay { adding(1 - weekday) }
    public var firstOfMonth: LocalDay { let c = civil; return LocalDay(year: c.year, month: c.month, day: 1) }
    /// The last day of this day's month.
    public var lastOfMonth: LocalDay {
        let c = civil
        return (c.month == 12 ? LocalDay(year: c.year + 1, month: 1, day: 1) : LocalDay(year: c.year, month: c.month + 1, day: 1)).adding(-1)
    }

    public func adding(_ days: Int) -> LocalDay { LocalDay(ordinal: ordinal + days) }

    /// Noon of this day in `timeZone`, for formatting: noon exists on every day, also on a daylight saving change.
    public func noon(in timeZone: TimeZone) -> Date {
        let guess = Date(timeIntervalSince1970: TimeInterval(ordinal * 86_400 + 43_200))
        return guess.addingTimeInterval(-TimeInterval(timeZone.secondsFromGMT(for: guess)))
    }

    /// `YYYY-MM-DD`
    public var description: String {
        let c = civil
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    public static func < (a: LocalDay, b: LocalDay) -> Bool { a.ordinal < b.ordinal }
}

/// Tokens of one model and one project of one CLI on one local day, with the estimate for them.
public struct TokenFact: Equatable, Sendable {
    public var day: LocalDay
    public var cli: InventoryCLI
    public var model: String
    public var project: String?
    public var counts: TokenCounts
    /// Nil when the model has no price.
    public var cost: Double?
}

/// Every fact of a ledger by local day, plus which sessions were active on which day.
public struct TokenFacts: Sendable {
    public let timeZone: TimeZone
    /// Sorted by day.
    public let facts: [TokenFact]
    /// Index into `facts`: the first fact of each day that has any.
    private let dayStart: [Int: Int]
    private let days: [LocalDay]
    /// Per CLI, the sorted days each session has tokens on.
    private let sessionDays: [InventoryCLI: [[Int]]]

    public init(ledger: TokenLedger, timeZone: TimeZone, prices: [String: ModelPrice] = Pricing.models) {
        self.timeZone = timeZone
        struct Key: Hashable { var day: Int; var cli: InventoryCLI; var model: String; var project: String? }
        var merged: [Key: TokenCounts] = [:]
        var sessions: [InventoryCLI: [String: Set<Int>]] = [:]
        var dayOfHour: [Int: Int] = [:]
        for file in ledger.files.values {
            let log = file.log
            for row in log.rows {
                let day = dayOfHour[row.hour] ?? LocalDay(utcHour: row.hour, in: timeZone).ordinal
                dayOfHour[row.hour] = day
                merged[Key(day: day, cli: log.cli, model: row.model, project: log.project), default: .zero] += row.counts
                sessions[log.cli, default: [:]][log.session, default: []].insert(day)
            }
        }
        var rate: [String: ModelPrice?] = [:]
        func price(_ model: String) -> ModelPrice? {
            if let known = rate[model] { return known }
            let found = Pricing.price(for: model, in: prices)
            rate[model] = found
            return found
        }
        let facts = merged.map { key, counts in
            TokenFact(day: LocalDay(ordinal: key.day), cli: key.cli, model: key.model, project: key.project, counts: counts,
                      cost: price(key.model).map { Pricing.usd(counts.usage, rate: $0) })
        }.sorted { a, b in
            (a.day.ordinal, a.cli.rawValue, a.model, a.project ?? "") < (b.day.ordinal, b.cli.rawValue, b.model, b.project ?? "")
        }
        var start: [Int: Int] = [:]
        for (i, fact) in facts.enumerated() where start[fact.day.ordinal] == nil { start[fact.day.ordinal] = i }
        self.facts = facts
        dayStart = start
        days = start.keys.sorted().map(LocalDay.init(ordinal:))
        sessionDays = sessions.mapValues { $0.values.map { $0.sorted() } }
    }

    /// The facts whose day lies in `range`, in day order.
    public func facts(in range: ClosedRange<LocalDay>) -> ArraySlice<TokenFact> {
        guard let lo = days.firstIndex(where: { $0 >= range.lowerBound }), days[lo] <= range.upperBound,
              let from = dayStart[days[lo].ordinal] else { return [] }
        let to = facts[from...].firstIndex { $0.day > range.upperBound } ?? facts.endIndex
        return facts[from..<to]
    }

    /// The first local day with tokens of `cli`; nil when it has none.
    public func firstDay(_ cli: InventoryCLI) -> LocalDay? { facts.first { $0.cli == cli }?.day }
    /// The first local day with any tokens.
    public var firstDay: LocalDay? { days.first }

    /// Sessions of `cli` with tokens on a day in `range`. A subagent log belongs to its parent session, so it adds none.
    public func sessions(_ cli: InventoryCLI, in range: ClosedRange<LocalDay>) -> Int {
        (sessionDays[cli] ?? []).filter { days in days.contains { range.contains(LocalDay(ordinal: $0)) } }.count
    }
}
