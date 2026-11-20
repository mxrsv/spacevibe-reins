import Foundation

/// A skill's place among the others, over the tab's rows of the scope before any filter (V5-R29). Rank is never printed on a
/// row; it exists as filters, the `Rank tier` grouping and the verdict's `Heavily used`.
enum SkillRankMark: String, CaseIterable, Sendable {
    case top10, top25, least10, never
    case top20, middle, bottom20
}

enum SkillRank {
    /// Marks per row key. The pool is the rows whose sessions are known, most sessions first, ties broken by name. `top10`
    /// and `top25` are positions among those with at least one session; `least10` is the last ten positions; `never` is the
    /// rows that never ran. The tiers are tie-safe: the cut at 20% of the pool is the session count at that position, a row
    /// is `top20` when it has at least the top cut and `bottom20` when it has at most the bottom cut, and when the two cuts are
    /// equal (every row alike) everyone is `middle`.
    static func marks(for rows: [LoadoutRow]) -> [String: Set<SkillRankMark>] {
        let pool = rows.compactMap { row -> (row: LoadoutRow, total: Int)? in
            row.skillUsage.sessions.map { (row, $0) }
        }.sorted { a, b in
            if a.total != b.total { return a.total > b.total }
            let byName = a.row.name.localizedCaseInsensitiveCompare(b.row.name)
            return byName == .orderedSame ? a.row.key < b.row.key : byName == .orderedAscending
        }
        let n = pool.count
        guard n > 0 else { return [:] }
        let k = max(1, Int((Double(n) * 0.2).rounded(.toNearestOrAwayFromZero)))
        let topCut = pool[k - 1].total
        let bottomCut = pool[n - k].total
        var out: [String: Set<SkillRankMark>] = [:]
        for (position, entry) in pool.enumerated() {
            var marks: Set<SkillRankMark> = []
            let total = entry.total
            if total > 0 && position < 10 { marks.insert(.top10) }
            if total > 0 && position < 25 { marks.insert(.top25) }
            if position >= n - 10 { marks.insert(.least10) }
            if entry.row.skillUsage.state == .neverRan { marks.insert(.never) }
            if topCut > bottomCut && total >= topCut { marks.insert(.top20) }
            else if topCut > bottomCut && total <= bottomCut { marks.insert(.bottom20) }
            else { marks.insert(.middle) }
            out[entry.row.key] = marks
        }
        return out
    }
}

/// A skill's status for the Status filter and grouping (V5-R14, V5-R29). `Dead` is not a skill status (S4).
enum SkillStatus: String, CaseIterable, Sendable {
    case heavy, ran, neverRan, unmeasurable, loading

    static func of(_ row: LoadoutRow, marks: Set<SkillRankMark>) -> SkillStatus {
        switch row.skillUsage.state {
        case .ran: marks.contains(.top20) ? .heavy : .ran
        case .neverRan: .neverRan
        case .unmeasurable: .unmeasurable
        case .loading: .loading
        }
    }

    var title: String {
        switch self {
        case .heavy: "Heavily used"
        case .ran: "Ran"
        case .neverRan: "Never ran"
        case .unmeasurable: "Unmeasurable"
        case .loading: "Counting sessions"
        }
    }

    /// The band's title: after a failed usage scan the rows without a count are not being counted any more.
    func title(scanFailed: Bool) -> String { self == .loading && scanFailed ? "Not counted" : title }

    var verdict: VerdictGlyph.Kind {
        switch self {
        case .heavy: .heavy
        case .ran: .used
        case .neverRan: .never
        case .unmeasurable, .loading: .nm
        }
    }
}

/// UTC calendar days, the grain of a skill's last session (`isoDay` in `core/internal/usage/lines.go`).
enum SkillDays {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whole days from `day` to the UTC day of `now`; nil when `day` is not a `YYYY-MM-DD`.
    static func daysAgo(_ day: String, now: Date) -> Int? {
        guard let from = date(day) else { return nil }
        return calendar.dateComponents([.day], from: from, to: calendar.startOfDay(for: now)).day
    }

    /// "today", "yesterday", "5 days ago", "3 weeks ago", "4 months ago": what a day-grained record can honestly say.
    static func phrase(_ day: String, now: Date) -> String {
        guard let days = daysAgo(day, now: now) else { return day }
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2 ..< 14: return "\(days) days ago"
        case 14 ..< 60: return "\(days / 7) weeks ago"
        default: return "\(days / 30) months ago"
        }
    }
}

/// The Skills filter: four fields (V5-R29; Status went in D70, Rank holds Never ran and the top tier).
typealias SkillsFilter = PickFilter<SkillsFilterField>

/// The four filter fields (V5-R29, D70). AND across fields, OR within one.
enum SkillsFilterField: String, FilterFieldKind {
    case cli, owner, rank, lastRan

    var title: String {
        switch self {
        case .cli: "CLI"
        case .owner: "Owner"
        case .rank: "Rank"
        case .lastRan: "Last ran"
        }
    }

    /// The first words of a chip: `Status is`, `CLI is`.
    var chipTitle: String { "\(title) is" }

    /// The values in menu order. Rank has two groups, headed in the menu by `rankGroups`.
    var values: [FilterValue] {
        switch self {
        case .cli:
            CLICatalog.current.inventoryCLIs.map { FilterValue($0.rawValue, "In \($0.label)", chip: $0.label) }
                + [FilterValue("both", "In both", chip: "Both"), FilterValue("one", "In one only", chip: "One only")]
        case .owner: [FilterValue("mine", "Mine"), FilterValue("plugin", "Plugin")]
        case .rank:
            [FilterValue("top10", "Top 10 most used"), FilterValue("top25", "Top 25 most used"),
             FilterValue("least10", "Least used 10"), FilterValue("never", "Never ran"),
             FilterValue("top20", "Top 20%"), FilterValue("middle", "Middle"), FilterValue("bottom20", "Bottom 20%")]
        case .lastRan:
            [FilterValue("today", "Today"), FilterValue("week", "This week"), FilterValue("old", "Over 30 days ago")]
        }
    }

    /// Menu headings and the id of the first value they head (Rank only).
    static let rankGroups: [(heading: String, firstValue: String)] = [("Most used", "top10"), ("Tier", "top20")]
}

enum SkillsGroup: String, CaseIterable, Sendable {
    case none, status, cli, owner, tier

    var title: String {
        switch self {
        case .none: "None"
        case .status: "Status"
        case .cli: "CLI presence"
        case .owner: "Owner"
        case .tier: "Rank tier"
        }
    }
}

enum SkillsOrder: String, CaseIterable, Sendable {
    case name, sessions, lastRan

    var title: String {
        switch self {
        case .name: "Name"
        case .sessions: "Sessions"
        case .lastRan: "Last run"
        }
    }

    /// The order line's words: "Ordered by sessions".
    var phrase: String {
        switch self {
        case .name: "name"
        case .sessions: "sessions"
        case .lastRan: "last run"
        }
    }
}

/// The Skills list as the head's Filter and View describe it, applied to the rows of one scope. Pure: a test gives rows and a
/// clock, a view reads `layout`.
struct SkillsQuery: Equatable, Sendable {
    var filter = SkillsFilter()
    var group = SkillsGroup.none
    var order = SkillsOrder.sessions

    /// The order line above the list (V5-R30).
    var orderLine: String { orderLine(scanFailed: false) }

    /// After a failed usage scan no row has a count, so an order by sessions or last run falls back to names: the line says
    /// the counts are missing instead of claiming an order it cannot give.
    func orderLine(scanFailed: Bool) -> String {
        "Ordered by \(order.phrase)" + (scanFailed && order != .name ? " \u{00B7} not counted" : "")
            + (group == .none ? "" : " \u{00B7} Grouped by \(group.title.lowercased())")
    }

    /// One band of the list, or the one headless group of a flat list.
    struct Group: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let status: SkillStatus?
        var rows: [LoadoutRow]
        /// Holds a row with the warning triangle: its band opens by default (V5-R55).
        var holdsProblem: Bool
    }

    struct Layout: Equatable, Sendable {
        var groups: [Group]
        var rows: [LoadoutRow] { groups.flatMap(\.rows) }
        var isGrouped: Bool
    }

    /// `rows` are the skills of the scope, unfiltered: the rank and the empty-category state read them all.
    func layout(_ rows: [LoadoutRow], now: Date, scanFailed: Bool = false) -> Layout {
        let marks = SkillRank.marks(for: rows)
        let kept = rows.filter { matches($0, marks: marks[$0.key] ?? [], now: now) }
        let ordered = kept.sorted(by: comparator(marks: marks))
        func group(_ id: String, _ title: String, status: SkillStatus? = nil, _ rows: [LoadoutRow]) -> Group? {
            rows.isEmpty ? nil : Group(id: id, title: title, status: status, rows: rows, holdsProblem: rows.contains { Self.holdsTriangle($0) })
        }
        let groups: [Group]
        switch self.group {
        case .none:
            groups = [group("flat", "", ordered)].compactMap { $0 }
        case .status:
            groups = SkillStatus.allCases.compactMap { status in
                group("status:\(status.rawValue)", status.title(scanFailed: scanFailed), status: status,
                      ordered.filter { SkillStatus.of($0, marks: marks[$0.key] ?? []) == status })
            }
        case .cli:
            groups = ([group("cli:both", "In both", ordered.filter { $0.presentCLIs.count == 2 })]
                + CLICatalog.current.inventoryCLIs.map { cli in
                    group("cli:\(cli.rawValue)", "Only \(cli.label)", ordered.filter { $0.presentCLIs == [cli] })
                }).compactMap { $0 }
        case .owner:
            groups = [group("owner:mine", "Mine", ordered.filter { $0.plugin == nil }), group("owner:plugin", "Plugin", ordered.filter { $0.plugin != nil })]
                .compactMap { $0 }
        case .tier:
            let tiers: [(SkillRankMark, String)] = [(.top20, "Top 20%"), (.middle, "Middle"), (.bottom20, "Bottom 20%")]
            groups = tiers.compactMap { tier in group("tier:\(tier.0.rawValue)", tier.1, ordered.filter { marks[$0.key]?.contains(tier.0) == true }) }
                + [group("tier:unranked", SkillStatus.loading.title(scanFailed: scanFailed), status: .loading, ordered.filter { marks[$0.key] == nil })]
                .compactMap { $0 }
        }
        return Layout(groups: groups, isGrouped: self.group != .none)
    }

    /// The warning triangle (never ran and not newly added) is the one thing a band holds as a problem.
    static func holdsTriangle(_ row: LoadoutRow) -> Bool {
        let usage = row.skillUsage
        return usage.state == .neverRan && usage.added == nil
    }

    func matches(_ row: LoadoutRow, marks: Set<SkillRankMark>, now: Date) -> Bool {
        SkillsFilterField.allCases.allSatisfy { field in
            guard let picked = filter.picks[field], !picked.isEmpty else { return true }
            return picked.contains { Self.test(field, value: $0, row: row, marks: marks, now: now) }
        }
    }

    private static func test(_ field: SkillsFilterField, value: String, row: LoadoutRow, marks: Set<SkillRankMark>, now: Date) -> Bool {
        switch field {
        case .cli:
            let present = row.presentCLIs
            switch value {
            case "both": return present.count == 2
            case "one": return present.count == 1
            default: return present.contains(CLIID(rawValue: value))
            }
        case .owner:
            return value == "plugin" ? row.plugin != nil : row.plugin == nil
        case .rank:
            return SkillRankMark(rawValue: value).map { marks.contains($0) } ?? false
        case .lastRan:
            guard let last = row.skillUsage.lastRan, let days = SkillDays.daysAgo(last, now: now) else { return false }
            switch value {
            case "today": return days < 1
            case "week": return days < 7
            case "old": return days > 30
            default: return false
            }
        }
    }

    private func comparator(marks: [String: Set<SkillRankMark>]) -> (LoadoutRow, LoadoutRow) -> Bool {
        func byName(_ a: LoadoutRow, _ b: LoadoutRow) -> Bool {
            let result = a.name.localizedCaseInsensitiveCompare(b.name)
            return result == .orderedSame ? a.key < b.key : result == .orderedAscending
        }
        switch order {
        case .name:
            return byName
        case .sessions:
            return { a, b in
                let x = a.skillUsage.sessions ?? -1, y = b.skillUsage.sessions ?? -1
                return x != y ? x > y : byName(a, b)
            }
        case .lastRan:
            return { a, b in
                let x = a.skillUsage.lastRan, y = b.skillUsage.lastRan
                if x != y { return (x ?? "") > (y ?? "") }
                return byName(a, b)
            }
        }
    }
}
