import Foundation
import Testing
@testable import ReinsCore

// Series, rankings and cost from a ledger built in memory, with a fixed clock and fixed time zones. Names and numbers are made up.

private let saigon = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let utc = TimeZone(identifier: "UTC")!
/// Monday 2026-11-02, 10:00 in Saigon.
private let now = Date(timeIntervalSince1970: TimeInterval(TokenLines.hour("2026-11-02T03:00:00Z")) * 3600)

private struct Row {
    var cli: InventoryCLI = .claude
    var session = "s1"
    var project: String? = "alpha-app"
    var at: String
    var model = "claude-opus-5-5"
    var counts: TokenCounts
}

private func ledger(_ rows: [Row]) -> TokenLedger {
    var files: [String: TokenLedgerFile] = [:]
    for row in rows {
        let key = "\(row.cli.rawValue)/\(row.session)/\(row.project ?? "-")"
        var file = files[key] ?? TokenLedgerFile(stamp: "1:1", v: TokenLedger.scanVersion, log: TokenLog(cli: row.cli, session: row.session, project: row.project, rows: []))
        file.log.rows.append(TokenRow(hour: TokenLines.hour(row.at), model: row.model, counts: row.counts))
        files[key] = file
    }
    return TokenLedger(files: files)
}

private func day(_ iso: String) -> LocalDay {
    let parts = iso.split(separator: "-").map { Int($0)! }
    return LocalDay(year: parts[0], month: parts[1], day: parts[2])
}

private func c(input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0) -> TokenCounts {
    TokenCounts(input: input, cacheWrite: cacheWrite, cacheRead: cacheRead, output: output)
}

@Suite("Token query")
struct TokenQueryTests {
    @Test("local days are plain arithmetic: civil dates, weekdays, Mondays and month ends")
    func localDays() {
        #expect(day("1970-01-01").ordinal == 0)
        #expect(day("2026-11-02").ordinal == 20759 && day("2026-11-02").weekday == 1)
        #expect(day("2026-11-01").weekday == 7 && day("2026-11-01").monday == day("2026-10-26"))
        #expect(day("2028-02-10").lastOfMonth == day("2028-02-29") && day("2026-12-31").adding(1) == day("2027-01-01"))
        #expect(day("2026-11-02").description == "2026-11-02" && day("1969-12-31").ordinal == -1)
    }

    @Test("a UTC hour counts on the machine's local day, also across midnight UTC and a daylight saving change")
    func dayCrossesUTC() {
        let l = ledger([
            Row(at: "2026-10-31T16:00:00Z", counts: c(output: 1)),  // 23:00 on Oct 31 in Saigon
            Row(at: "2026-10-31T17:00:00Z", counts: c(output: 10)), // 00:00 on Nov 1 in Saigon
        ])
        let local = TokenQuery(ledger: l, now: now, timeZone: saigon).buckets(.day)
        #expect(local.first { $0.start == day("2026-10-31") }?.claude.counts.output == 1)
        #expect(local.first { $0.start == day("2026-11-01") }?.claude.counts.output == 10)
        let inUTC = TokenQuery(ledger: l, now: now, timeZone: utc).buckets(.day)
        #expect(inUTC.first { $0.start == day("2026-10-31") }?.claude.counts.output == 11)

        // Los Angeles leaves daylight saving on Sunday 2026-11-01: midnight is 07:00Z before it and 08:00Z after.
        let dst = ledger([
            Row(at: "2026-11-01T06:00:00Z", counts: c(output: 1)),   // 23:00 PDT, Oct 31
            Row(at: "2026-11-01T07:00:00Z", counts: c(output: 10)),  // 00:00 PDT, Nov 1
            Row(at: "2026-11-02T07:00:00Z", counts: c(output: 100)), // 23:00 PST, Nov 1
        ])
        let la = TokenQuery(ledger: dst, now: now, timeZone: losAngeles)
        #expect(la.tally(.claude, in: day("2026-10-31")...day("2026-10-31")).counts.output == 1)
        #expect(la.tally(.claude, in: day("2026-11-01")...day("2026-11-01")).counts.output == 110)
    }

    @Test("series: the last 30 days, 12 Monday weeks, every month from the first counted day; newest first, today first")
    func series() {
        let q = TokenQuery(ledger: ledger([Row(at: "2026-08-11T05:00:00Z", counts: c(input: 1))]), now: now, timeZone: saigon)
        let days = q.buckets(.day)
        #expect(days.count == 30 && days.first?.start == day("2026-11-02") && days.last?.start == day("2026-10-04"))
        #expect(q.span(.day) == day("2026-10-04")...day("2026-11-02"))
        let weeks = q.buckets(.week)
        #expect(weeks.count == 12 && weeks.first?.start == day("2026-11-02") && weeks.first?.end == day("2026-11-02"))
        #expect(weeks.last?.start == day("2026-08-17") && weeks[1].range == day("2026-10-26")...day("2026-11-01"))
        let months = q.buckets(.month)
        #expect(months.map(\.start) == [day("2026-11-01"), day("2026-10-01"), day("2026-09-01"), day("2026-08-01")])
        #expect(months.last?.claude.counts.input == 1 && months.first?.end == day("2026-11-02"))
        #expect(TokenQuery(ledger: TokenLedger(), now: now, timeZone: saigon).buckets(.month).map(\.start) == [day("2026-11-01")])
    }

    @Test("four kinds per CLI; a model pick leaves the other CLI empty, a project pick keeps both")
    func kindsAndPicks() {
        let q = TokenQuery(ledger: ledger([
            Row(at: "2026-11-01T02:00:00Z", counts: c(input: 1, cacheWrite: 2, cacheRead: 3, output: 4)),
            Row(at: "2026-11-01T02:00:00Z", model: "claude-sonnet-5-5", counts: c(input: 10)),
            Row(cli: .codex, session: "r1", at: "2026-11-01T03:00:00Z", model: "gpt-6-astra", counts: c(input: 100, cacheRead: 200, output: 300)),
        ]), now: now, timeZone: saigon)
        let span = q.span(.day)
        #expect(q.tally(.claude, in: span).counts == c(input: 11, cacheWrite: 2, cacheRead: 3, output: 4))
        #expect(q.tally(.codex, in: span).counts == c(input: 100, cacheRead: 200, output: 300))
        #expect(q.tally(.codex, in: span).counts.fresh == 400)
        let pick = TokenPick.model(.claude, "claude-opus-5-5")
        #expect(q.tally(.claude, in: span, pick: pick).counts.total == 10)
        #expect(q.tally(.codex, in: span, pick: pick).isEmpty)
        #expect(q.tally(.codex, in: span, pick: .project("alpha-app")).counts.total == 600)
        #expect(q.buckets(.day, pick: pick).first { $0.start == day("2026-11-01") }?.both.counts.total == 10)
    }

    @Test("cost keeps the priced subtotal apart from tokens with no price; a model with no price yields no cost, never 0")
    func cost() throws {
        let prices = ["claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheWrite: 5, cacheWriteLong: 8, cacheRead: 0.2)]
        let q = TokenQuery(ledger: ledger([
            Row(at: "2026-11-01T02:00:00Z", counts: c(input: 1_000_000, cacheRead: 2_000_000, output: 500_000)),
            Row(at: "2026-11-01T02:00:00Z", model: "claude-zeta-9", counts: c(input: 70, output: 30)),
            Row(cli: .codex, session: "r1", at: "2026-11-01T03:00:00Z", model: "gpt-zeta", counts: c(input: 5)),
        ]), now: now, timeZone: saigon)
        let p = TokenQuery(facts: TokenFacts(ledger: ledger([
            Row(at: "2026-11-01T02:00:00Z", counts: c(input: 1_000_000, cacheRead: 2_000_000, output: 500_000)),
            Row(at: "2026-11-01T02:00:00Z", model: "claude-zeta-9", counts: c(input: 70, output: 30)),
        ]), timeZone: saigon, prices: prices), today: q.today)
        let claude = p.tally(.claude, in: p.span(.day))
        #expect(claude.cost == 4 + 10 + 0.4)
        #expect(claude.unpriced == 100)
        let codex = q.tally(.codex, in: q.span(.day))
        #expect(codex.cost == nil && codex.unpriced == 5 && codex.value(.cost) == 0)
        #expect((codex + TokenTally.empty).cost == nil)
        #expect(q.unpricedModels(in: q.span(.day)) == ["claude-zeta-9", "gpt-zeta"])
        #expect(q.tally(.claude, in: day("2026-10-01")...day("2026-10-02")).cost == nil)
    }

    @Test("the per-model estimate is Activity's, one-hour cache writes included")
    func sameFormulaAsActivity() throws {
        let counts = TokenCounts(input: 1234, cacheWrite: 50_000, cacheWrite1h: 20_000, cacheRead: 900_000, output: 4321)
        let facts = TokenFacts(ledger: ledger([Row(at: "2026-11-01T02:00:00Z", counts: counts)]), timeZone: saigon)
        let fact = try #require(facts.facts.first)
        #expect(Pricing.estimate([("claude-opus-5-5", counts.usage)]) == .usd(try #require(fact.cost)))
    }

    @Test("models and projects rank by the measure; tokens with no project are a share, not a row")
    func rankings() {
        let q = TokenQuery(ledger: ledger([
            Row(at: "2026-11-01T02:00:00Z", counts: c(input: 10, cacheRead: 1_000)),
            Row(at: "2026-11-01T02:00:00Z", model: "claude-sonnet-5-5", counts: c(input: 500)),
            Row(at: "2026-11-01T02:00:00Z", model: "claude-zeta-9", counts: c(input: 900)),
            Row(session: "s2", project: "beta-api", at: "2026-11-01T04:00:00Z", model: "claude-sonnet-5-5", counts: c(input: 50)),
            Row(session: "s3", project: nil, at: "2026-11-01T05:00:00Z", model: "claude-sonnet-5-5", counts: c(input: 2460)),
            Row(cli: .codex, session: "r1", project: "beta-api", at: "2026-11-01T03:00:00Z", model: "gpt-6-astra", counts: c(input: 3000)),
        ]), now: now, timeZone: saigon)
        let span = q.span(.day)
        #expect(q.models(.claude, in: span, by: .tokens).map(\.name) == ["claude-sonnet-5-5", "claude-opus-5-5", "claude-zeta-9"])
        #expect(q.models(.claude, in: span, by: .fresh).map(\.name) == ["claude-sonnet-5-5", "claude-zeta-9", "claude-opus-5-5"])
        #expect(q.models(.claude, in: span, by: .cost).last?.name == "claude-zeta-9")
        #expect(q.projects(in: span, by: .tokens).map(\.name) == ["beta-api", "alpha-app"])
        #expect(q.projects(in: span, by: .tokens).first?.codex.counts.input == 3000)
        #expect(q.unnamedShare(.claude, in: span) == 0.5)
        #expect(q.unnamedShare(.codex, in: span) == 0)
    }

    @Test("the day counting starts from, per CLI; sessions count once in a range, a subagent log adds none")
    func startAndSessions() {
        let q = TokenQuery(ledger: ledger([
            Row(at: "2026-10-20T02:00:00Z", counts: c(input: 1)),
            Row(at: "2026-10-21T02:00:00Z", counts: c(input: 1)),
            Row(project: "worktree-of-s1", at: "2026-10-21T03:00:00Z", counts: c(input: 1)),
            Row(session: "s2", at: "2026-10-25T02:00:00Z", counts: c(input: 1)),
            Row(cli: .codex, session: "r1", at: "2026-10-28T02:00:00Z", model: "gpt-6-astra", counts: c(input: 1)),
        ]), now: now, timeZone: saigon)
        #expect(q.firstDay(.claude) == day("2026-10-20") && q.firstDay(.codex) == day("2026-10-28"))
        #expect(q.sessions(.claude, in: q.span(.day)) == 2)
        #expect(q.sessions(.claude, in: day("2026-10-21")...day("2026-10-24")) == 1)
        #expect(q.sessions(.codex, in: q.span(.day)) == 1)
        #expect(TokenQuery(ledger: TokenLedger(), now: now, timeZone: saigon).firstDay(.claude) == nil)
    }
}
