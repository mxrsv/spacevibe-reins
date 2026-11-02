import Foundation
import ReinsCore
import Testing
@testable import Reins

// The Tokens board's logic without a window: figures, the cut axis, and the keyboard. Names and numbers are made up.

private let utc = TimeZone(identifier: "UTC")!
/// 2026-11-02 12:00 UTC.
private let now = Date(timeIntervalSince1970: 1_793_620_800)
private let todayHour = Int(now.timeIntervalSince1970 / 3600)

private func ledger(_ days: [(daysAgo: Int, cli: InventoryCLI, model: String, input: Int)]) -> TokenLedger {
    var files: [String: TokenLedgerFile] = [:]
    for (index, day) in days.enumerated() {
        let log = TokenLog(cli: day.cli, session: "s\(index)", project: index % 2 == 0 ? "alpha-app" : nil,
                           rows: [TokenRow(hour: todayHour - 24 * day.daysAgo, model: day.model, counts: TokenCounts(input: day.input))])
        files["\(day.cli.rawValue)/s\(index)"] = TokenLedgerFile(stamp: "1:1", v: TokenLedger.scanVersion, log: log)
    }
    return TokenLedger(files: files)
}

@MainActor
private func model(_ ledger: TokenLedger) -> TokensModel {
    let env = AppEnvironment(roots: nil, proc: FixtureProcessAdapter.empty, toasts: ToastCenter(announce: false))
    let model = TokensModel(env: env, timeZone: utc, now: { now })
    model.preview(result: TokenScanResult(ledger: ledger, files: 1), now: now)
    return model
}

@Suite("Tokens board")
@MainActor
struct TokensBoardTests {
    @Test("token and dollar figures read like the mock; no price is never $0")
    func figures() {
        #expect(TokensFormat.tokens(16_000_000_000) == "16B")
        #expect(TokensFormat.tokens(14_100_000_000) == "14.1B")
        #expect(TokensFormat.tokens(1_870_000_000) == "1.87B")
        #expect(TokensFormat.tokens(634_000_000) == "634M")
        #expect(TokensFormat.tokens(29_400_000) == "29.4M")
        #expect(TokensFormat.tokens(142_000) == "142K" && TokensFormat.tokens(980) == "980")
        #expect(TokensFormat.usd(8209.4) == "~$8,209" && TokensFormat.usd(46.2) == "~$46" && TokensFormat.usd(1.3) == "~$1.30")
        #expect(TokensFormat.value(TokenTally(counts: TokenCounts(input: 5), cost: nil, unpriced: 5), .cost) == "no price")
        #expect(TokensFormat.value(.empty, .cost) == "–")
        #expect(TokensFormat.isPartial(TokenTally(counts: TokenCounts(input: 9), cost: 1, unpriced: 4), .cost))
        #expect(TokensPriceTable.rate(0.125) == "$0.125" && TokensPriceTable.rate(4) == "$4" && TokensPriceTable.rate(0.2) == "$0.2")
        #expect(TokensFormat.percent(0.955) == "95.5%")
    }

    @Test("bucket labels: Today, Yesterday, a weekday; a week's span; a month")
    func labels() throws {
        let m = model(ledger([(0, .claude, "claude-opus-5-5", 10)]))
        let board = try #require(m.board)
        #expect(board.label(board.buckets[0]) == "Today")
        #expect(board.label(board.buckets[1]) == "Yesterday")
        #expect(board.label(board.buckets[2]) == "Sat, Oct 31")
        m.period = .week
        let weeks = try #require(m.board)
        #expect(weeks.label(weeks.buckets[1]) == "Oct 26 – Nov 1")
        m.period = .month
        let months = try #require(m.board)
        #expect(months.label(months.buckets[0]) == "November 2026")
    }

    @Test("one bucket far above the rest is cut at a round number near twice the second largest")
    func cutAxis() throws {
        let m = model(ledger([(1, .claude, "claude-opus-5-5", 1000), (2, .claude, "claude-opus-5-5", 100), (3, .codex, "gpt-6-astra", 90)]))
        m.measure = .tokens
        let board = try #require(m.board)
        #expect(board.axis == TokensBoard.Axis(top: 200, cut: 1))
        #expect(TokensBoard.nice(0) == 1 && TokensBoard.nice(3) == 5 && TokensBoard.nice(12) == 20)
        #expect(board.peak?.start == board.buckets[1].start)
        // Without a stand-out bucket the axis is the next round number above the largest.
        let even = model(ledger([(1, .claude, "claude-opus-5-5", 120), (2, .claude, "claude-opus-5-5", 100)]))
        even.measure = .tokens
        #expect(even.board?.axis == TokensBoard.Axis(top: 200, cut: 0))
    }

    @Test("arrows move the picked bucket, return opens its kinds, escape closes the price table, then clears the scope")
    func keyboard() throws {
        let m = model(ledger([(0, .claude, "claude-opus-5-5", 10), (1, .codex, "gpt-6-astra", 20)]))
        let columns = try #require(m.board?.columns.map(\.id))
        #expect(m.move(1) == columns.first)
        #expect(m.move(-1) == columns.first)
        m.selectedID = nil
        #expect(m.move(-1) == columns.last)
        #expect(m.move(-1) == columns[columns.count - 2])
        #expect(m.openSelected())
        #expect(m.expanded == [columns[columns.count - 2]])
        m.toggle(.model(.codex, "gpt-6-astra"))
        #expect(m.board?.scoped(.claude).isEmpty == true && m.board?.scoped(.codex).counts.input == 20)
        m.isPriceTableOpen = true
        #expect(m.escape() && !m.isPriceTableOpen && m.hasScope)
        #expect(m.escape() && !m.hasScope)
        #expect(!m.escape() && !m.openSelected())
    }

    @Test("a new period clears the picked bucket and the open rows, and the summary ignores the scope")
    func periodAndSummary() throws {
        let m = model(ledger([(0, .claude, "claude-opus-5-5", 10), (5, .claude, "claude-sonnet-5-5", 30)]))
        m.select(try #require(m.board?.buckets[0].id))
        m.toggleExpanded(try #require(m.selectedID))
        let board = try #require(m.board)
        #expect(board.scoped(.claude).counts.input == 10)
        #expect(board.summary(.claude).counts.input == 40)
        m.period = .week
        #expect(m.selectedID == nil && m.expanded.isEmpty)
        m.select(try #require(m.board?.buckets[0].id))
        m.select(try #require(m.board?.buckets[0].id))
        #expect(m.selectedID == nil)
    }

    @Test("the tab registers fourth, so Command 4 opens it, and its hints follow the scope")
    func registration() throws {
        let tabs = TabRegistry.makeTabs()
        #expect(tabs.map(\.id).firstIndex(of: TokensTab.tabID) == 3)
        let m = model(ledger([(0, .claude, "claude-opus-5-5", 10)]))
        let tab = TokensTab(model: m)
        #expect(tab.hints.map(\.label) == ["Day"])
        m.selectedID = m.board?.buckets[0].id
        #expect(tab.hints.map(\.label) == ["Day", "Token kinds", "Clear scope"])
        #expect(tab.paletteActions.contains { $0.id == "tokens.clear" })
    }
}
