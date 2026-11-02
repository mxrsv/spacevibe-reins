import Foundation
import ReinsCore

/// Words and numbers of the Tokens board. Pure functions, so tests pin them without a window.
enum TokensFormat {
    /// "16B", "14.1B", "1.87B", "634M", "29.4M", "142K", "980".
    static func tokens(_ n: Int) -> String {
        let a = abs(Double(n))
        func trimmed(_ value: Double, _ digits: Int, _ unit: String) -> String {
            var text = String(format: "%.\(digits)f", value)
            if text.contains(".") {
                while text.hasSuffix("0") { text.removeLast() }
                if text.hasSuffix(".") { text.removeLast() }
            }
            return text + unit
        }
        if a >= 1e9 { return trimmed(Double(n) / 1e9, a >= 1e10 ? 1 : 2, "B") }
        if a >= 1e6 { return trimmed(Double(n) / 1e6, a >= 1e8 ? 0 : 1, "M") }
        if a >= 1e3 { return trimmed(Double(n) / 1e3, a >= 1e5 ? 0 : 1, "K") }
        return String(n)
    }

    /// Always marked as an estimate: "~$8,209", "~$46", "~$1.30".
    static func usd(_ value: Double) -> String {
        if value >= 100 {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return "~$" + (formatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded())))
        }
        return "~$" + String(format: value >= 10 ? "%.0f" : "%.2f", value)
    }

    /// What a tally shows for a measure: "–" when it holds no token, "no price" for a cost none of its tokens has.
    static func value(_ tally: TokenTally, _ measure: TokenMeasure) -> String {
        if tally.isEmpty { return "–" }
        switch measure {
        case .tokens: return tokens(tally.counts.total)
        case .fresh: return tokens(tally.counts.fresh)
        case .cost: return tally.cost.map(usd) ?? "no price"
        }
    }

    /// A cost that leaves tokens out: the warning sign goes next to it.
    static func isPartial(_ tally: TokenTally, _ measure: TokenMeasure) -> Bool {
        measure == .cost && tally.cost != nil && tally.unpriced > 0
    }

    /// The tooltip of a cell: the four kinds and the estimate.
    static func kindsTip(_ tally: TokenTally) -> String {
        let c = tally.counts
        var lines = ["Input \(tokens(c.input))", "Cache write \(tokens(c.cacheWrite))", "Cache read \(tokens(c.cacheRead))", "Output \(tokens(c.output))",
                     "Est. cost \(tally.cost.map(usd) ?? "not measured")"]
        if tally.unpriced > 0, tally.cost != nil { lines.append("\(tokens(tally.unpriced)) tokens have no price") }
        return lines.joined(separator: "\n")
    }

    /// An axis label: "$1K", "$500", "4.2B", "0".
    static func axis(_ value: Double, _ measure: TokenMeasure) -> String {
        if value <= 0 { return "0" }
        let text = tokens(Int(value.rounded()))
        return measure == .cost ? "$" + text : text
    }

    static func percent(_ share: Double) -> String { String(format: "%.1f%%", share * 100) }

    static func measureTitle(_ measure: TokenMeasure) -> String {
        switch measure {
        case .tokens: return "All tokens"
        case .fresh: return "New only"
        case .cost: return "Est. cost"
        }
    }

    static func periodTitle(_ period: TokenPeriod) -> String {
        switch period {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    /// What the summary covers: "Last 30 days", "Last 12 weeks", "All time".
    static func spanName(_ period: TokenPeriod) -> String {
        switch period {
        case .day: return "Last 30 days"
        case .week: return "Last 12 weeks"
        case .month: return "All time"
        }
    }

    static func seriesTitle(_ period: TokenPeriod) -> String {
        switch period {
        case .day: return "By day"
        case .week: return "By week"
        case .month: return "By month"
        }
    }

    static func rowsTitle(_ period: TokenPeriod) -> String {
        switch period {
        case .day: return "Days"
        case .week: return "Weeks"
        case .month: return "Months"
        }
    }

    private static func formatted(_ day: LocalDay, _ format: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: day.noon(in: timeZone))
    }

    /// "Oct 26"
    static func short(_ day: LocalDay, _ timeZone: TimeZone) -> String { formatted(day, "MMM d", timeZone) }

    /// A bucket's row name: "Today", "Yesterday", "Mon, Oct 26"; "Oct 26 – Nov 1"; "October 2026".
    static func bucketLabel(_ bucket: TokenBucket, period: TokenPeriod, today: LocalDay, timeZone: TimeZone) -> String {
        switch period {
        case .day:
            if bucket.start == today { return "Today" }
            if bucket.start == today.adding(-1) { return "Yesterday" }
            return formatted(bucket.start, "EEE, MMM d", timeZone)
        case .week:
            return "\(short(bucket.start, timeZone)) – \(short(bucket.start.adding(6), timeZone))"
        case .month:
            return formatted(bucket.start, "MMMM yyyy", timeZone)
        }
    }

    /// The tick under a column: "Oct 26" for a day or a week, "Nov 26" for a month.
    static func tick(_ bucket: TokenBucket, period: TokenPeriod, timeZone: TimeZone) -> String {
        period == .month ? formatted(bucket.start, "MMM yy", timeZone) : short(bucket.start, timeZone)
    }

    /// "Claude Code from Jul 17, Codex from Jul 17"; a CLI with nothing counted says so.
    static func countingFrom(_ query: TokenQuery) -> String {
        CLIKind.allCases.map { cli in
            query.firstDay(cli.engine).map { "\(cli.label) from \(short($0, query.facts.timeZone))" } ?? "\(cli.label): nothing counted yet"
        }.joined(separator: ", ")
    }

    /// "1,234" with grouping.
    static func count(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}
