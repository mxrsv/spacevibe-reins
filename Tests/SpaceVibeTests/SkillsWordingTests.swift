import Foundation
import Testing
@testable import SpaceVibe

/// V5-A5: the Never ran warning and the newly added note, plugin skills read-only, the detected CLIs and the write plans; every
/// sentence is vocabulary-checked against GLOSSARY.md (V5-R45).
@Suite("Skills wording and write plans")
struct SkillsWordingTests {
    private typealias F = SkillRowsFixture
    private let events = ["claude": ["Stop"], "codex": ["Stop"]]

    // MARK: Warning slot

    @Test("Never ran in one CLI: the warn triangle, a plain sentence, Remove offered")
    func neverRanOne() throws {
        let warning = try #require(SkillsWording.warning(for: F.row("a", claude: F.counted(0))))
        #expect(warning.kind == .neverRan && warning.label == "Never ran" && warning.offersRemove && warning.plugin == nil)
        #expect(warning.sentence == "Never ran in Claude Code. Nothing in the local logs shows a session.")
    }

    @Test("Never ran in both CLIs names neither alone")
    func neverRanBoth() throws {
        let warning = try #require(SkillsWording.warning(for: F.row("a", claude: F.counted(0), codex: F.counted(0))))
        #expect(warning.sentence == "Never ran in either CLI. Nothing in the local logs shows a session.")
    }

    @Test("a newly added skill reads Never ran with the neutral clock and the core's own wording, no invented time")
    func newlyAdded() throws {
        let day = try #require(SkillsWording.warning(for: F.row("a", claude: F.addedToday)))
        #expect(day.kind == .newlyAdded && day.label == "Never ran, newly added")
        #expect(day.sentence == "Never ran. Added in the last 24 hours, so no session may have used it yet.")
        let log = try #require(SkillsWording.warning(for: F.row("b", claude: F.addedAfterLog)))
        #expect(log.sentence == "Never ran. Added after the newest log SpaceVibe counted, so no session may have used it yet.")
        for sentence in [day.sentence, log.sentence] { #expect(!sentence.contains(" ago"), "no time of day exists to say \"ago\"") }
    }

    @Test("no logs is Unmeasurable with the clock; a skill that ran, or whose scan is running, has no warning")
    func otherStates() throws {
        let none = try #require(SkillsWording.warning(for: F.row("a", codex: F.noLogs)))
        #expect(none.kind == .unmeasurable && none.label == "Unmeasurable" && !none.offersRemove)
        #expect(none.sentence == "SpaceVibe found no Codex logs, so it cannot count sessions.")
        #expect(SkillsWording.warning(for: F.row("b", claude: F.counted(4))) == nil)
        #expect(SkillsWording.warning(for: F.row("c", claude: F.scanning)) == nil)
    }

    @Test("a plugin's skill that never ran is read-only: no Remove, and the popover says who owns it")
    func pluginWarning() throws {
        let warning = try #require(SkillsWording.warning(for: F.row("neon", claude: F.counted(0), owner: "neon")))
        #expect(warning.plugin == "neon" && !warning.offersRemove)
    }

    // MARK: Verdict and meters

    @Test("the verdict says what the sessions say, one sentence per case, and never mentions a CLI that is not installed")
    func verdicts() throws {
        func verdict(_ row: LoadoutRow, detected: [CoreCLI] = [.claude, .codex]) throws -> SkillsWording.Verdict {
            let marks = SkillRank.marks(for: [row])
            return try #require(SkillsWording.verdict(for: row, status: SkillStatus.of(row, marks: marks[row.key] ?? []), detected: detected))
        }
        let heavy = SkillsWording.verdict(for: F.row("a", claude: F.counted(142)), status: .heavy, detected: [.claude, .codex])
        #expect(heavy?.text == "Ran only in Claude Code. One of the busiest skills you have." && heavy?.small == "Codex does not have it yet.")
        #expect(SkillsWording.verdict(for: F.row("a", claude: F.counted(142)), status: .heavy, detected: [.claude])?.small == nil)
        let one = try verdict(F.row("b", claude: F.counted(1)))
        #expect(one.title == "Ran" && one.text == "Used only in Claude Code. Codex does not have it.")
        #expect(one.small == "Adding it gives Codex the same skill with a fresh count.")
        let both = SkillsWording.verdict(for: F.row("c", claude: F.counted(20), codex: F.counted(5)), status: .ran, detected: [.claude, .codex])
        #expect(both?.text == "Used in both CLIs.")
        let never = try verdict(F.row("d", claude: F.counted(0)))
        #expect(never.title == "Never ran" && never.text == "Installed in Claude Code. Nothing in the local logs shows a session." && never.small == "A good candidate to remove.")
        let fresh = try verdict(F.row("e", claude: F.addedToday))
        #expect(fresh.small == "Added in the last 24 hours, so it is not a candidate to remove yet.")
        let plugin = try verdict(F.row("f", claude: F.counted(0), owner: "neon"))
        #expect(plugin.small == "Owned by the neon plugin, so SpaceVibe can read it but not change it.")
        #expect(SkillsWording.verdict(for: F.row("g", claude: F.scanning), status: .loading, detected: [.claude]) == nil)
    }

    @Test("Never ran names the date the logs reach back to once the scan has one, and keeps the undated sentence before")
    func neverRanNamesTheSpan() throws {
        func text(_ row: LoadoutRow, since: String?) throws -> String {
            try #require(SkillsWording.verdict(for: row, status: .neverRan, detected: [.claude, .codex], since: since)).text
        }
        let one = F.row("a", claude: F.counted(0))
        #expect(try text(one, since: "2026-10-01") == "Installed in Claude Code. No session in the local logs since 2026-10-01.")
        #expect(try text(one, since: nil) == "Installed in Claude Code. Nothing in the local logs shows a session.")
        let both = F.row("b", claude: F.counted(0), codex: F.counted(0))
        #expect(try text(both, since: "2026-10-01") == "Installed in both CLIs. No session in the local logs since 2026-10-01.")
        let half = F.row("c", claude: F.counted(0), codex: F.noLogs)
        #expect(try text(half, since: "2026-10-01").contains("No session in the local logs since 2026-10-01 in Claude Code"))
    }

    @Test("a sentence says where the sessions happened, not where the file is: 142 in Claude Code and 0 in Codex is all in Claude Code")
    func verdictFollowsTheSessions() throws {
        func verdict(_ row: LoadoutRow, _ status: SkillStatus) throws -> SkillsWording.Verdict {
            try #require(SkillsWording.verdict(for: row, status: status, detected: [.claude, .codex]))
        }
        // In both CLIs, sessions in one only.
        let heavy = try verdict(F.row("a", claude: F.counted(142), codex: F.counted(0)), .heavy)
        #expect(heavy.text == "Ran only in Claude Code. One of the busiest skills you have." && heavy.small == "It has not run in Codex.")
        let fresh = try verdict(F.row("b", claude: F.counted(142), codex: F.addedToday), .heavy)
        #expect(fresh.text == "Ran only in Claude Code. One of the busiest skills you have.")
        #expect(fresh.small == "It has not run in Codex: that copy was added in the last 24 hours.")
        let ran = try verdict(F.row("c", claude: F.counted(0), codex: F.counted(7)), .ran)
        #expect(ran.text == "Used only in Codex." && ran.small == "It has not run in Claude Code.")
        let unlogged = try verdict(F.row("d", claude: F.counted(7), codex: F.noLogs), .ran)
        #expect(unlogged.text == "Used only in Claude Code." && unlogged.small == "SpaceVibe found no Codex logs, so it cannot count sessions there.")
        // Sessions in both: both are named.
        #expect(try verdict(F.row("e", claude: F.counted(20), codex: F.counted(5)), .ran).text == "Used in both CLIs.")
        #expect(try verdict(F.row("f", claude: F.counted(80), codex: F.counted(30)), .heavy).text == "Ran in both CLIs. One of the busiest skills you have.")
        // The skill is in one CLI only: the CLI that has it is the CLI that ran it.
        #expect(try verdict(F.row("g", claude: F.counted(9)), .ran).text == "Used only in Claude Code. Codex does not have it.")
        // Never ran names the CLIs whose logs were counted.
        let neverBoth = try verdict(F.row("h", claude: F.counted(0), codex: F.counted(0)), .neverRan)
        #expect(neverBoth.text == "Installed in both CLIs. Nothing in the local logs shows a session in either.")
        let neverOne = try verdict(F.row("i", claude: F.counted(0), codex: F.noLogs), .neverRan)
        #expect(neverOne.text == "Installed in both CLIs. Nothing in the local logs shows a session in Claude Code, and SpaceVibe found no Codex logs.")
        let warning = try #require(SkillsWording.warning(for: F.row("j", claude: F.counted(0), codex: F.noLogs)))
        #expect(warning.sentence == "Never ran in Claude Code. Nothing in the local logs shows a session.")
        #expect(SkillsWording.warning(for: F.row("k", claude: F.counted(0), codex: F.counted(0)))?.sentence == "Never ran in either CLI. Nothing in the local logs shows a session.")
        // No sentence about a skill that ran claims both CLIs ran it unless both did.
        for row in [F.row("l", claude: F.counted(5), codex: F.counted(0)), F.row("m", claude: F.counted(5), codex: F.addedToday)] {
            for status in [SkillStatus.heavy, .ran] { #expect(try !verdict(row, status).text.contains("both CLIs")) }
        }
    }

    @Test("a meter shows the count and the last day; a CLI without the skill shows a dash, never a zero; an unknown count is a dash too")
    func meters() {
        let row = F.row("a", claude: F.counted(50, last: "2026-11-05"))
        let claude = SkillsWording.meter(for: row, cli: .claude, maxSessions: 100, now: F.now)
        #expect(claude.figure == 50 && claude.share == 0.5 && claude.caption == "Last ran" && claude.emphasis == "yesterday")
        let codex = SkillsWording.meter(for: row, cli: .codex, maxSessions: 100, now: F.now)
        #expect(codex.figure == nil && codex.share == nil && codex.status == "Not in Codex" && codex.caption == "Codex does not have this skill.")
        #expect(SkillsWording.meter(for: F.row("b", claude: F.counted(0)), cli: .claude, maxSessions: 100, now: F.now).emphasis == "never")
        #expect(SkillsWording.meter(for: F.row("c", claude: F.scanning), cli: .claude, maxSessions: 100, now: F.now).figure == nil)
        #expect(SkillsWording.meter(for: F.row("d", codex: F.noLogs), cli: .codex, maxSessions: 100, now: F.now).caption == "No Codex logs to count from")
        let plugin = F.row("e", claude: F.counted(3), owner: "neon")
        #expect(SkillsWording.meter(for: plugin, cli: .codex, maxSessions: 100, now: F.now).caption == "Plugin-owned skills stay in their CLI")
        #expect(SkillsWording.meter(for: F.row("f", claude: F.addedToday), cli: .claude, maxSessions: 100, now: F.now).caption == "Added in the last 24 hours")
    }

    @Test("no sentence uses a banned word (V5-R45): runs, dead, pending, not counted yet, not measured")
    func vocabulary() {
        let rows = [F.row("a", claude: F.counted(0)), F.row("b", claude: F.addedToday), F.row("c", claude: F.counted(7), codex: F.counted(2)),
                    F.row("d", codex: F.noLogs), F.row("e", claude: F.counted(0), owner: "neon")]
        var text: [String] = []
        for row in rows {
            let marks = SkillRank.marks(for: rows)[row.key] ?? []
            let status = SkillStatus.of(row, marks: marks)
            if let warning = SkillsWording.warning(for: row) { text += [warning.label, warning.sentence] }
            if let verdict = SkillsWording.verdict(for: row, status: status, detected: [.claude, .codex]) { text += [verdict.title, verdict.text, verdict.small ?? ""] }
            for cli in CoreCLI.allCases {
                let meter = SkillsWording.meter(for: row, cli: cli, maxSessions: 10, now: F.now)
                text += [meter.caption, meter.status ?? "", meter.emphasis ?? ""]
            }
        }
        text += SkillStatus.allCases.map(\.title) + SkillsQuery().orderLine.components(separatedBy: " ")
        let banned = ["runs", "dead", "pending", "not counted", "not measured", "unused"]
        for sentence in text.map({ $0.lowercased() }) {
            for word in banned { #expect(!sentence.contains(word), "\"\(sentence)\" contains \"\(word)\"") }
        }
    }

    // MARK: Detected CLIs, logo modes, write plans

    @Test("the strip lists the CLIs limits.read does not call not installed; before a reading, the ones that hold a skill")
    func detected() {
        func entry(_ cli: CoreLimitsCLI, _ state: CoreLimitsState) -> CoreLimitsEntry { CoreLimitsEntry(cli: cli, state: state, plan: nil, source: nil, at: nil, windows: []) }
        let rows = [F.row("a", claude: F.counted(1))]
        #expect(LoadoutRows.detectedCLIs(limits: [entry(.claude, .measured), entry(.codex, .notInstalled), entry(.gemini, .notMeasurable)], rows: rows) == [.claude])
        #expect(LoadoutRows.detectedCLIs(limits: [entry(.claude, .notRecorded), entry(.codex, .measured)], rows: rows) == [.claude, .codex])
        #expect(LoadoutRows.detectedCLIs(limits: [], rows: rows) == [.claude])
        #expect(LoadoutRows.detectedCLIs(limits: [], rows: []) == [])
    }

    @Test("logo modes: a lit one toggles unless it is the only copy; a dim one toggles when a copy is allowed; a plugin's or a project's skill is read-only")
    func logoModes() {
        let both = F.row("a", claude: F.counted(1), codex: F.counted(1))
        #expect(LoadoutRows.logoMode(both, cli: .claude, events: events) == .toggles && LoadoutRows.logoMode(both, cli: .codex, events: events) == .toggles)
        let one = F.row("b", claude: F.counted(1))
        #expect(LoadoutRows.logoMode(one, cli: .claude, events: events) == .onlyCopy, "the last lit logo is not a toggle (D53)")
        #expect(LoadoutRows.logoMode(one, cli: .codex, events: events) == .toggles)
        let plugin = F.row("c", claude: F.counted(1), owner: "neon")
        #expect(LoadoutRows.logoMode(plugin, cli: .claude, events: events) == .readOnly && LoadoutRows.logoMode(plugin, cli: .codex, events: events) == .readOnly)
        let project = F.row("d", claude: F.counted(1), project: "/work/app")
        #expect(LoadoutRows.logoMode(project, cli: .claude, events: events) == .readOnly && LoadoutRows.logoMode(project, cli: .codex, events: events) == .readOnly)
    }

    @Test("add plans copy each skill that lacks the CLI and skip a plugin's, a project's and one that already has it")
    func addPlans() {
        let rows = [F.row("a", claude: F.counted(1)), F.row("b", claude: F.counted(1), codex: F.counted(1)),
                    F.row("c", claude: F.counted(1), owner: "neon"), F.row("d", claude: F.counted(1), project: "/work/app")]
        let plan = LoadoutRows.addWrites(rows, to: .codex, events: events)
        #expect(plan.steps == [.copy(id: "claude:skill:global:a", to: .codex)] && plan.rows == 1)
        #expect(plan.skipped == 2, "the plugin's and the project's skill; the one that has it is not a skip")
    }

    @Test("remove plans: from every CLI, or from one CLI skipping an only copy; a plugin's skill is never written")
    func removePlans() {
        let both = F.row("a", claude: F.counted(1), codex: F.counted(1))
        let one = F.row("b", claude: F.counted(1))
        let plugin = F.row("c", claude: F.counted(1), codex: F.counted(1), owner: "neon")
        let everywhere = LoadoutRows.removeWrites([both, one, plugin], from: nil)
        #expect(everywhere.steps == [.remove(id: "claude:skill:global:a", from: .claude), .remove(id: "codex:skill:global:a", from: .codex),
                                     .remove(id: "claude:skill:global:b", from: .claude)])
        #expect(everywhere.rows == 2 && everywhere.skipped == 1)
        let fromClaude = LoadoutRows.removeWrites([both, one], from: .claude)
        #expect(fromClaude.steps == [.remove(id: "claude:skill:global:a", from: .claude)] && fromClaude.skipped == 1, "b's only copy is not removed by a toggle")
        #expect(LoadoutRows.removeWrites([plugin], from: .claude).steps.isEmpty)
    }

    @Test("toast labels name the skill, or the count, and say how many were left as they are")
    func labels() {
        let a = F.row("a", claude: F.counted(1)), b = F.row("b", claude: F.counted(1))
        #expect(SkillsWording.addLabel([a], to: .codex, skipped: 0) == "Added a to Codex")
        #expect(SkillsWording.addLabel([a, b], to: .codex, skipped: 1) == "Added 2 skills to Codex (1 left as they are)")
        #expect(SkillsWording.removeLabel([a], from: nil, skipped: 0) == "Removed a")
        #expect(SkillsWording.removeLabel([a, b], from: .claude, skipped: 0) == "Removed 2 skills from Claude Code")
    }
}
