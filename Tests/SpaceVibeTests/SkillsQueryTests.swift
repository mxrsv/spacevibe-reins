import Foundation
import Testing
@testable import SpaceVibe

/// V5-A5: the Skills list as the head's Filter and View describe it, on rows built the way the app builds them.
@Suite("Skills list")
struct SkillsQueryTests {
    private typealias F = SkillRowsFixture

    /// ponytail 100 (today), impeccable 50 + 30, explain 20 + 5, ghost (Codex only) 12, neon (plugin) 5, tdd 5 (66 days ago),
    /// review-change never ran, skill-creator newly added, webapp-testing never ran in both, loading (scan not finished).
    private var rows: [LoadoutRow] {
        let specs: [(name: String, claude: CoreUsageCell?, codex: CoreUsageCell?)] = [
            ("ponytail", F.counted(100, last: "2026-11-06"), nil),
            ("impeccable", F.counted(50, last: "2026-11-05"), F.counted(30, last: "2026-11-01")),
            ("explain", F.counted(20, last: "2026-10-30"), F.counted(5, last: "2026-10-20")),
            ("ghost", nil, F.counted(12, last: "2026-11-06")),
            ("neon-postgres", F.counted(5, last: "2026-11-04"), nil),
            ("tdd", F.counted(5, last: "2026-09-01"), nil),
            ("review-change", F.counted(0), nil),
            ("skill-creator", F.addedToday, nil),
            ("webapp-testing", F.counted(0), F.counted(0)),
            ("loading-skill", F.scanning, nil),
        ]
        return F.rows(specs, owners: ["neon-postgres": "neon"])
    }

    private func names(_ query: SkillsQuery, _ rows: [LoadoutRow]? = nil) -> [String] {
        query.layout(rows ?? self.rows, now: F.now).rows.map(\.name)
    }

    private func filtered(_ field: SkillsFilterField, _ values: String...) -> [String] {
        var query = SkillsQuery()
        for value in values { query.filter.toggle(field, value) }
        return names(query)
    }

    // MARK: Order

    @Test("the flat list is ordered by sessions descending, ties by name, an unknown count last")
    func flatOrder() {
        #expect(names(SkillsQuery()) == ["ponytail", "impeccable", "explain", "ghost", "neon-postgres", "tdd",
                                         "review-change", "skill-creator", "webapp-testing", "loading-skill"])
    }

    @Test("Order by name ignores case; Order by last run puts the latest first and a skill that never ran last, ties by name")
    func otherOrders() {
        var query = SkillsQuery()
        query.order = .name
        #expect(names(query) == ["explain", "ghost", "impeccable", "loading-skill", "neon-postgres", "ponytail", "review-change", "skill-creator", "tdd", "webapp-testing"])
        query.order = .lastRan
        // 2026-11-06: ghost, ponytail; 11-05 impeccable; 11-04 neon; 10-30 explain; 09-01 tdd; no day: the rest by name.
        #expect(names(query) == ["ghost", "ponytail", "impeccable", "neon-postgres", "explain", "tdd", "loading-skill", "review-change", "skill-creator", "webapp-testing"])
        #expect(query.orderLine == "Ordered by last run")
        query.group = .owner
        #expect(query.orderLine == "Ordered by last run \u{00B7} Grouped by owner")
    }

    // MARK: Status, usage, ranks

    @Test("status: Never ran covers a counted zero and a newly added file; Heavily used is the top 20% tier; Dead does not exist")
    func statuses() {
        let all = rows
        let marks = SkillRank.marks(for: all)
        func status(_ name: String) -> SkillStatus { SkillStatus.of(all.first { $0.name == name }!, marks: marks[all.first { $0.name == name }!.key] ?? []) }
        #expect(status("ponytail") == .heavy && status("impeccable") == .heavy)
        #expect(status("explain") == .ran && status("neon-postgres") == .ran && status("tdd") == .ran)
        #expect(status("review-change") == .neverRan && status("webapp-testing") == .neverRan)
        #expect(status("skill-creator") == .neverRan, "a newly added file reads as Never ran with a note, not as a separate state")
        #expect(status("loading-skill") == .loading)
        #expect(SkillStatus.allCases.map(\.title) == ["Heavily used", "Ran", "Never ran", "Unmeasurable", "Counting sessions"])
    }

    @Test("a pending cell is three facts: the scan, no logs, a new file; and the core's own never-ran flag is not used")
    func pendingCells() throws {
        #expect(SkillCell(F.scanning) == .loading && SkillCell(F.noLogs) == .noLogs)
        #expect(SkillCell(F.addedToday) == .added(.lastDay) && SkillCell(F.addedAfterLog) == .added(.afterNewestLog))
        let noLogs = F.row("a", claude: F.noLogs)
        #expect(noLogs.skillUsage.state == .unmeasurable && noLogs.skillUsage.sessions == nil)
        let added = F.row("b", claude: F.addedAfterLog)
        #expect(added.skillUsage.state == .neverRan && added.skillUsage.added == .afterNewestLog && added.skillUsage.sessions == 0)
        // One CLI counted zero and the other has no logs: the skill never ran where it was counted.
        #expect(F.row("c", claude: F.counted(0), codex: F.noLogs).skillUsage.state == .neverRan)
        // Any session anywhere is Ran, and a scan still running anywhere is Loading.
        #expect(F.row("d", claude: F.counted(3), codex: F.noLogs).skillUsage.state == .ran)
        #expect(F.row("e", claude: F.counted(3), codex: F.scanning).skillUsage.state == .loading)
        #expect(F.row("f", claude: F.counted(2, last: "2026-11-01"), codex: F.counted(1, last: "2026-11-03")).skillUsage.lastRan == "2026-11-03")
    }

    @Test("rank marks: positions, tiers, the never ran set, and rows with an unknown count have none")
    func rankMarks() throws {
        let all = rows
        let marks = SkillRank.marks(for: all)
        func of(_ name: String) -> Set<SkillRankMark> { marks[all.first { $0.name == name }!.key] ?? [] }
        #expect(of("ponytail") == [.top10, .top25, .least10, .top20])
        #expect(of("impeccable") == [.top10, .top25, .least10, .top20])
        #expect(of("explain") == [.top10, .top25, .least10, .middle])
        #expect(of("review-change") == [.least10, .never, .bottom20])
        #expect(of("webapp-testing") == [.least10, .never, .bottom20])
        #expect(marks[all.first { $0.name == "loading-skill" }!.key] == nil)
        // top10 and top25 need a session: a row at zero is never among the most used.
        #expect(!of("skill-creator").contains(.top10) && of("skill-creator").contains(.never))
    }

    @Test("tiers are tie-safe: every row at the cut count, and equal rows are all Middle")
    func tiersWithTies() {
        func tiers(_ totals: [Int]) -> [String: SkillRankMark] {
            let built = F.rows(totals.enumerated().map { ("s\($0.offset)", F.counted($0.element), nil) })
            let marks = SkillRank.marks(for: built)
            return Dictionary(uniqueKeysWithValues: built.map { row in
                (row.name, [SkillRankMark.top20, .middle, .bottom20].first { marks[row.key]?.contains($0) == true }!)
            })
        }
        // Five rows, 20% is one: the cut is 10, three rows have it, so all three are in the top tier; the two at 1 are the bottom.
        #expect(tiers([10, 10, 10, 1, 1]) == ["s0": .top20, "s1": .top20, "s2": .top20, "s3": .bottom20, "s4": .bottom20])
        #expect(tiers([3, 3, 3, 3]) == ["s0": .middle, "s1": .middle, "s2": .middle, "s3": .middle])
        // One row alone is both ends of its own pool: nothing to tell apart.
        #expect(tiers([7]) == ["s0": .middle])
        #expect(tiers([9, 5, 4, 3, 1]) == ["s0": .top20, "s1": .middle, "s2": .middle, "s3": .middle, "s4": .bottom20])
    }

    @Test("Top 10 and Top 25 are positions among skills that ran, Least used 10 the last ten positions")
    func rankPositions() {
        let many = F.rows((0 ..< 30).map { ("s\(String(format: "%02d", $0))", F.counted(100 - $0), nil) })
        var query = SkillsQuery()
        query.filter.toggle(.rank, "top10")
        #expect(names(query, many) == (0 ..< 10).map { "s\(String(format: "%02d", $0))" })
        query = SkillsQuery()
        query.filter.toggle(.rank, "top25")
        #expect(names(query, many).count == 25)
        query = SkillsQuery()
        query.filter.toggle(.rank, "least10")
        #expect(names(query, many) == (20 ..< 30).map { "s\(String(format: "%02d", $0))" })
    }

    // MARK: Filters

    @Test("Status filter: Never ran and Heavily used")
    func statusFilter() {
        #expect(filtered(.status, "neverRan") == ["review-change", "skill-creator", "webapp-testing"])
        #expect(filtered(.status, "heavy") == ["ponytail", "impeccable"])
    }

    @Test("CLI filter: In Claude Code, In Codex, In both, In one only")
    func cliFilter() {
        #expect(filtered(.cli, "claude") == ["ponytail", "impeccable", "explain", "neon-postgres", "tdd", "review-change", "skill-creator", "webapp-testing", "loading-skill"])
        #expect(filtered(.cli, "codex") == ["impeccable", "explain", "ghost", "webapp-testing"])
        #expect(filtered(.cli, "both") == ["impeccable", "explain", "webapp-testing"])
        #expect(filtered(.cli, "one") == ["ponytail", "ghost", "neon-postgres", "tdd", "review-change", "skill-creator", "loading-skill"])
    }

    @Test("Owner filter: Mine and Plugin")
    func ownerFilter() {
        #expect(filtered(.owner, "plugin") == ["neon-postgres"])
        #expect(filtered(.owner, "mine").count == 9 && !filtered(.owner, "mine").contains("neon-postgres"))
    }

    @Test("Rank filter: each of the seven values")
    func rankFilter() {
        #expect(filtered(.rank, "top10") == ["ponytail", "impeccable", "explain", "ghost", "neon-postgres", "tdd"])
        #expect(filtered(.rank, "top25") == ["ponytail", "impeccable", "explain", "ghost", "neon-postgres", "tdd"])
        #expect(filtered(.rank, "least10").count == 9, "fewer than ten skills: every one is among the least used ten")
        #expect(filtered(.rank, "never") == ["review-change", "skill-creator", "webapp-testing"])
        #expect(filtered(.rank, "top20") == ["ponytail", "impeccable"])
        #expect(filtered(.rank, "middle") == ["explain", "ghost", "neon-postgres", "tdd"])
        #expect(filtered(.rank, "bottom20") == ["review-change", "skill-creator", "webapp-testing"])
    }

    @Test("Last ran filter: Today, This week, Over 30 days ago, Never, by UTC day")
    func lastRanFilter() {
        #expect(filtered(.lastRan, "today") == ["ponytail", "ghost"])
        #expect(filtered(.lastRan, "week") == ["ponytail", "impeccable", "ghost", "neon-postgres"])
        #expect(filtered(.lastRan, "old") == ["tdd"])
        #expect(filtered(.lastRan, "never") == ["review-change", "skill-creator", "webapp-testing", "loading-skill"])
    }

    @Test("values within a field are ORed, fields are ANDed, and a toggle twice clears the pick")
    func andOr() {
        #expect(filtered(.status, "neverRan", "heavy") == ["ponytail", "impeccable", "review-change", "skill-creator", "webapp-testing"])
        var query = SkillsQuery()
        query.filter.toggle(.status, "neverRan")
        query.filter.toggle(.status, "heavy")
        query.filter.toggle(.cli, "one")
        #expect(names(query) == ["ponytail", "review-change", "skill-creator"])
        query.filter.toggle(.owner, "plugin")
        #expect(names(query).isEmpty)
        #expect(query.filter.isOn && query.filter.chips.map(\.value.id) == ["neverRan", "heavy", "one", "plugin"])
        query.filter.toggle(.owner, "plugin")
        query.filter.toggle(.cli, "one")
        query.filter.toggle(.status, "heavy")
        query.filter.toggle(.status, "neverRan")
        #expect(!query.filter.isOn)
        query.filter.toggle(.status, "heavy")
        query.filter.clear()
        #expect(!query.filter.isOn && names(query).count == 10)
    }

    @Test("filters never shrink the rank: a skill keeps its tier when others are filtered out")
    func rankIgnoresFilters() {
        var query = SkillsQuery()
        query.filter.toggle(.owner, "plugin")
        query.filter.toggle(.rank, "middle")
        #expect(names(query) == ["neon-postgres"])
        query.filter.toggle(.rank, "top20")
        #expect(names(query) == ["neon-postgres"])
    }

    // MARK: Group by

    @Test("Group by Status: bands in status order, none for an empty status, rows keep the order")
    func groupByStatus() {
        var query = SkillsQuery()
        query.group = .status
        let layout = query.layout(rows, now: F.now)
        #expect(layout.isGrouped)
        #expect(layout.groups.map(\.title) == ["Heavily used", "Ran", "Never ran", "Counting sessions"])
        #expect(layout.groups.map { $0.rows.map(\.name) } == [["ponytail", "impeccable"], ["explain", "ghost", "neon-postgres", "tdd"],
                                                              ["review-change", "skill-creator", "webapp-testing"], ["loading-skill"]])
        #expect(layout.groups.map(\.holdsProblem) == [false, false, true, false])
    }

    @Test("a band holds a problem only when a row shows the warning triangle: a newly added skill does not")
    func problemBands() {
        var query = SkillsQuery()
        query.group = .status
        let onlyNew = query.layout([F.row("fresh", claude: F.addedToday)], now: F.now)
        #expect(onlyNew.groups.map(\.holdsProblem) == [false])
        let one = query.layout([F.row("old", claude: F.counted(0))], now: F.now)
        #expect(one.groups.map(\.holdsProblem) == [true])
    }

    @Test("Group by CLI presence, Owner and Rank tier")
    func otherGroups() {
        var query = SkillsQuery()
        query.group = .cli
        var layout = query.layout(rows, now: F.now)
        #expect(layout.groups.map(\.title) == ["In both", "Only Claude Code", "Only Codex"])
        #expect(layout.groups.map { $0.rows.map(\.name) } == [["impeccable", "explain", "webapp-testing"],
                                                              ["ponytail", "neon-postgres", "tdd", "review-change", "skill-creator", "loading-skill"], ["ghost"]])
        query.group = .owner
        layout = query.layout(rows, now: F.now)
        #expect(layout.groups.map(\.title) == ["Mine", "Plugin"] && layout.groups[1].rows.map(\.name) == ["neon-postgres"])
        query.group = .tier
        layout = query.layout(rows, now: F.now)
        #expect(layout.groups.map(\.title) == ["Top 20%", "Middle", "Bottom 20%", "Counting sessions"])
        #expect(layout.groups.map { $0.rows.map(\.name) } == [["ponytail", "impeccable"], ["explain", "ghost", "neon-postgres", "tdd"],
                                                              ["review-change", "skill-creator", "webapp-testing"], ["loading-skill"]])
        query.group = .none
        #expect(!query.layout(rows, now: F.now).isGrouped)
    }

    @Test("a grouping drops no skill: every row is in exactly one band")
    func groupsCoverEveryRow() {
        for group in SkillsGroup.allCases {
            var query = SkillsQuery()
            query.group = group
            #expect(query.layout(rows, now: F.now).rows.map(\.name).sorted() == rows.map(\.name).sorted(), "\(group)")
        }
    }

    // MARK: Days, tab counts

    @Test("a day is worded by what a UTC date can say: today, yesterday, days, weeks, months")
    func dayPhrases() {
        #expect(SkillDays.phrase("2026-11-06", now: F.now) == "today")
        #expect(SkillDays.phrase("2026-11-05", now: F.now) == "yesterday")
        #expect(SkillDays.phrase("2026-11-01", now: F.now) == "5 days ago")
        #expect(SkillDays.phrase("2026-10-20", now: F.now) == "2 weeks ago")
        #expect(SkillDays.phrase("2026-08-01", now: F.now) == "3 months ago")
        #expect(SkillDays.phrase("nonsense", now: F.now) == "nonsense")
    }

    @Test("the Skills tab counts the skills of the scope, not its subagents or hooks")
    func tabCounts() {
        let data = LoadoutData(rows: rows, scopes: [], countsByScope: [:], problems: [], events: [:], globalCount: rows.count)
        let counts = AgentsCounts(loadout: data, rules: nil)
        #expect(counts.skills == 10 && counts.subagents == 0 && counts.hooks == 0)
    }
}
