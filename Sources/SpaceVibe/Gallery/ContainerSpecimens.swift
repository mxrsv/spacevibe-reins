import SwiftUI

/// The v5 container blocks in every state of the spec's Components table, on the content panel's ground (`bgPanel`), as
/// `system/components.html` shows them. Hover and focus are drawn with `.specimen(_:)`; the open states come from a
/// gallery-own `OpenStateStore`, so collapsing works in the live gallery and the app's store is untouched. Synthetic names.
struct ContainerSpecimens: View {
    @State private var store = OpenStateStore()
    @State private var picked: Set<String> = ["explain"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            panel("Card: open with a count, collapsed, with a state glyph and an action, loading, empty, capped at a maximum height") { cards }
            panel("Answer card: needs you (verdict box, fixes, more marked), nothing needs you, loading") { answers }
            panel("Band: open, collapsed, problem, hover, focus; closed bands 10 apart, then the two-column grid of Hooks") { bands }
            panel("Row: rest, hover, current, picked, current and picked, focus; in a list with the lead slot, then in a card") { rows }
            panel("Bar, share, count and secondary text cells: neutral, warn, danger, unknown") { cells }
            panel("Stats with 2, 3 and 4 figures; column chart with empty buckets and the current one") { figures }
            panel("Empty state: no items, nothing matches with Clear filters (in a card, in a list); loading skeleton") { empties }
        }
    }

    // MARK: - Cards

    private var cards: some View {
        pairs([
            ("open, rows, count", AnyView(Tile("Next resets", count: "4", isOpen: open("next")) { resetRows })),
            ("collapsed", AnyView(Tile("Source", isOpen: open("source", false)) { resetRows })),
            ("state glyph and a 28-high action", AnyView(
                Tile("Can't copy to Codex", count: "6", state: StateMark(.warn, label: "2 need a look"), isOpen: open("cant")) {
                    ListRows {
                        ListRow("notify") { MetaCell(text: "No Notification event") }
                        ListRow("ask-review") { MetaCell(text: "Can't run prompt handlers") }
                    }
                } actions: { Button {} label: { ActionLabel("Why") }.buttonStyle(ActionButtonStyle(size: .compact)) })),
            ("loading", AnyView(Tile("Usage windows", layout: .bare, isOpen: open("loading")) { LoadingSkeleton() })),
            ("empty", AnyView(Tile("Hooks", count: "0", layout: .bare, isOpen: open("empty")) {
                QuietEmptyState("No hooks", message: "Neither CLI has a hook configured.")
            })),
            ("capped: the body scrolls inside", AnyView(Tile("Rules", count: "36", maxHeight: 220, isOpen: open("capped")) {
                ListRows { ForEach(["Bash(git status)", "Bash(npm test *)", "Read(*)", "Edit(src/**)", "WebFetch(*)", "Bash(rm -rf *)"], id: \.self) { ListRow($0) } }
            })),
        ])
    }

    private var resetRows: some View {
        ListRows {
            resetRow("16:20", .codex, "Codex 5-hour")
            resetRow("17:40", .claude, "Claude Code 5-hour")
            resetRow("Sun 18:00", .codex, "Codex Weekly Spark")
            resetRow("Thu 09:00", .claude, "Claude Code Weekly")
        }
    }

    private func resetRow(_ time: String, _ cli: CoreLimitsCLI, _ name: String) -> some View {
        ListRow(name) {
            MetaCell(text: time, width: 72, alignment: .leading)
            CLIMark(cli, size: .control)
        } trailing: {
            WarningSlot()
        }
    }

    // MARK: - Answer

    private var answers: some View {
        pairs([
            ("needs you", AnyView(
                AnswerCard(sentence: "1 hook can't run, 3 are missing in Codex.",
                           verdict: VerdictBox(glyph: .used, glyphLabel: "Advice", title: "typecheck-edit",
                                               text: "PostToolUse runs a script that is gone.", small: "Added 3 weeks ago."),
                           moreMarked: 2, isOpen: open("answer")) {
                    Button {} label: { ActionLabel("Remove", glyph: .trash) }.buttonStyle(ActionButtonStyle(kind: .danger))
                    Button {} label: { ActionLabel("Open file", glyph: .open) }.buttonStyle(ActionButtonStyle())
                } headerActions: {
                    Button {} label: { ActionLabel("Copy /usage", key: "C") }.buttonStyle(ActionButtonStyle(size: .compact))
                })),
            ("nothing needs you", AnyView(AnswerCard(sentence: "Nothing needs you.", isOpen: open("calm")))),
            ("loading", AnyView(AnswerCard(sentence: nil, isOpen: open("answer-loading")))),
        ])
    }

    // MARK: - Bands

    private var bands: some View {
        pairs([
            ("open (logo, count, state glyph), then collapsed with the stale extras; 32 above the second", AnyView(
                Tile("Usage windows", isOpen: open("usage")) {
                    BandStack {
                        Band("Claude Code", count: 3, state: StateMark(.warn, label: "A window is low"), isOpen: open("band-claude")) {
                            windowRows
                        } lead: { CLIMark(CoreLimitsCLI.claude, size: .control) }
                        Band("Codex", count: 4, isOpen: open("band-codex", false)) { windowRows } lead: {
                            CLIMark(CoreLimitsCLI.codex, size: .control)
                        } extras: {
                            StaleNote("read 8 h ago")
                        }
                        Band("Gemini CLI", isOpen: open("band-gemini", false)) { EmptyView() } lead: { CLIMark(CoreLimitsCLI.gemini, size: .control) }
                    }
                })),
            ("problem (danger glyph, open), hover, focus", AnyView(
                Tile("Hooks", count: "21", isOpen: open("hooks")) {
                    VStack(alignment: .leading, spacing: Space.s8) {
                        Band("PostToolUse", count: 4, state: StateMark(.danger, label: "A hook in this event can't run"), isOpen: open("post")) {
                            ListRows {
                                ListRow("format-on-save", lead: CategoryGlyph.hook, isCurrent: true) { MetaCell(text: "Edit|Write", width: 96) }
                                ListRow("typecheck-edit", lead: CategoryGlyph.hook) { MetaCell(text: "Edit", width: 96) }
                            }
                        }
                        Band("SessionStart", count: 1, isOpen: open("hover-band", false)) { EmptyView() }.specimen(.hover)
                        Band("PreToolUse", count: 4, isOpen: open("focus-band", false)) { EmptyView() }.specimen(.focus)
                    }
                })),
            ("closed bands, stacked 10 apart", AnyView(
                Tile("Permissions", isOpen: open("perm")) {
                    BandStack {
                        ForEach(["Bash", "Edit/Write", "Read", "Web"], id: \.self) { family in
                            Band(family, count: 3, isOpen: open("perm-\(family)", false)) { EmptyView() }
                        }
                    }
                })),
            ("Hooks: closed bands in a two-column grid, 8 apart, 32 under an open band", AnyView(
                Tile("Hooks", count: "21", isOpen: open("grid")) {
                    BandStack(closedRuns: .grid) {
                        Band("Stop", count: 3, isOpen: open("grid-stop")) {
                            ListRows { ListRow("stop-summary", lead: CategoryGlyph.hook) { MetaCell(text: "", width: 96) } }
                        }
                        ForEach(["SessionStart", "UserPromptSubmit", "PreToolUse", "SubagentStop", "SessionEnd"], id: \.self) { event in
                            Band(event, count: 1, isOpen: open("grid-\(event)", false)) { EmptyView() }
                        }
                        Band("Notification", count: 1, isOpen: open("grid-notification", false)) { EmptyView() } lead: {
                            CLIMark(CoreLimitsCLI.claude, size: .control)
                        }
                    }
                })),
        ])
    }

    private var windowRows: some View {
        ListRows {
            ListRow("5-hour", nameWidth: 128, isCurrent: true) { BarCell(share: 0.78); ShareCell(percent: 78); slot }
            ListRow("Weekly", nameWidth: 128) { BarCell(share: 0.41); ShareCell(percent: 41); slot }
            ListRow("Weekly Opus", nameWidth: 128) {
                BarCell(share: 0.12, tone: .warn); ShareCell(percent: 12)
                WarningSlot(mark: StateMark(.warn, label: "Low"), detail: "Weekly Opus has 12% left.", id: "gallery.weekly-opus") {
                    PopoverSentence("Weekly Opus has 12% left.")
                }
            }
        }
    }

    private var slot: some View { WarningSlot() }

    // MARK: - Rows

    private var rows: some View {
        HStack(alignment: .top, spacing: Space.s24) {
            VStack(alignment: .leading, spacing: Space.s8) {
                caption("in a list (bgPanel): rest, hover, current, picked, current + picked + focus, focus")
                ListRows {
                    listRow("ponytail")
                    listRow("impeccable").specimen(.hover)
                    listRow("diagnosing-bugs", current: true)
                    listRow("explain")
                    listRow("tidy-git", current: true, picked: true).specimen(.focus)
                    listRow("kyant-kanban").specimen(.focus)
                    listRow("review-change")
                    listRow("neon-postgres")
                }
                .padding(.horizontal, Space.s8)
            }
            .frame(width: halfCanvas)
            VStack(alignment: .leading, spacing: Space.s8) {
                caption("in a card (bgRaise), no lead: rest, hover, current and focus, rest")
                Tile("Failed commands", count: "4 commands", isOpen: open("failed")) {
                    ListRows {
                        ListRow("pnpm tsc --noEmit") { MetaCell(text: "exit 2", width: 120); CountCell(text: "8 times", width: 64) }
                        ListRow("swift test").specimen(.hover)
                        ListRow("go vet ./...", isCurrent: true) { MetaCell(text: "undefined: foldCodex", width: 120); CountCell(text: "3 times", width: 64) }
                            .specimen(.focus)
                        ListRow("npm run lint") { MetaCell(text: "2 problems", width: 120); CountCell(text: "1 time", width: 64) }
                    }
                }
            }
            .frame(width: halfCanvas)
        }
    }

    private func listRow(_ name: String, current: Bool = false, picked: Bool = false) -> some View {
        let isPicked = picked || self.picked.contains(name)
        return ListRow(name, lead: CategoryGlyph.skill, isCurrent: current, isPicked: isPicked, onPick: { toggle(name) }, onActivate: {}) {
            let mode: LogoToggleMode = name == "neon-postgres" ? .readOnly : .toggles
            LogoStrip {
                LogoToggle(cli: .claude, isLit: true, mode: mode) {}
                LogoToggle(cli: .codex, isLit: name.count.isMultiple(of: 2), mode: mode) {}
            }
            if name == "review-change" {
                WarningSlot(mark: StateMark(.warn, label: "Never ran"), detail: "Never ran in Claude Code. Added 3 weeks ago.",
                            id: "gallery.review-change") {
                    PopoverSentence("Never ran in Claude Code. Added 3 weeks ago.")
                }
            } else {
                WarningSlot()
            }
        }
    }

    private func toggle(_ name: String) {
        if picked.contains(name) { picked.remove(name) } else { picked.insert(name) }
    }

    // MARK: - Cells

    private var cells: some View {
        Tile("Cells", isOpen: open("cells")) {
            ListRows {
                ListRow("neutral, 78% left", nameWidth: 200) { BarCell(share: 0.78); ShareCell(percent: 78); CountCell(text: "12 sessions", width: 96) }
                ListRow("warn, 18% left", nameWidth: 200) { BarCell(share: 0.18, tone: .warn); ShareCell(percent: 18); CountCell(text: "3 times", width: 96) }
                ListRow("danger, 4% left", nameWidth: 200) { BarCell(share: 0.04, tone: .danger); ShareCell(percent: 4); CountCell(text: "41 edits", width: 96) }
                ListRow("unknown (reset passed)", nameWidth: 200) { BarCell(share: nil); ShareCell(percent: nil); CountCell(text: "never ran", width: 96) }
                ListRow("secondary text") { MetaCell(text: "PreToolUse \u{00B7} Write|Edit", width: 200); MetaCell(text: "spacevibe-bench", width: 112) }
            }
        }
    }

    // MARK: - Figures

    private var figures: some View {
        pairs([
            ("stats: 2, 3, 4 figures", AnyView(
                Tile("Today", layout: .content, isOpen: open("stats")) {
                    StatFigures(figures: [.init(value: "1,204", label: "tool calls today"), .init(value: "$3.42", label: "estimated cost today")])
                    StatFigures(figures: [.init(value: "1,204", label: "tool calls today"), .init(value: "$3.42", label: "estimated cost today"),
                                          .init(value: "1 h 12 min", label: "longest running session")])
                    StatFigures(figures: [.init(value: "9", label: "sessions"), .init(value: "1,204", label: "tool calls"),
                                          .init(value: "2", label: "failed"), .init(value: "41", label: "file edits")])
                })),
            ("column chart: 14 buckets, two empty, today bright", AnyView(
                Tile("Today", layout: .content, isOpen: open("chart")) {
                    ColumnChart(buckets: chartBuckets, currentIndex: chartBuckets.count - 1,
                                axis: ["13 days ago", "estimated cost per day, last 14 days", "today"],
                                summary: "Estimated cost per day, last 14 days")
                })),
        ])
    }

    private var chartBuckets: [ColumnChart.Bucket] {
        [2.1, 3.4, 0, 1.2, 4.8, 3.9, 2.2, 0, 5.6, 4.1, 3.3, 2.7, 4.4, 3.42].enumerated().map { index, value in
            ColumnChart.Bucket(id: index, value: value, label: String(format: "$%.2f", value))
        }
    }

    // MARK: - Empty states

    private var empties: some View {
        pairs([
            ("no items, in a card", AnyView(Tile("Subagents", count: "0", layout: .bare, isOpen: open("none")) {
                QuietEmptyState("No subagents", message: "Neither CLI has a subagent yet.")
            })),
            ("nothing matches, with Clear filters, in a card", AnyView(Tile("Subagents", count: "0", layout: .bare, isOpen: open("nomatch")) {
                QuietEmptyState("Nothing matches", message: "No subagent fits these filters.") {
                    Button {} label: { ActionLabel("Clear filters") }.buttonStyle(ActionButtonStyle(size: .bar))
                }
            })),
            ("nothing matches, in a list", AnyView(QuietEmptyState("Nothing matches", message: "No skill fits these filters.", placement: .list) {
                Button {} label: { ActionLabel("Clear filters") }.buttonStyle(ActionButtonStyle(size: .bar))
            })),
            ("loading skeleton, in a card", AnyView(Tile("Answer", layout: .bare, isOpen: open("skeleton")) { LoadingSkeleton() })),
        ])
    }

    // MARK: - Layout

    private func open(_ id: String, _ byDefault: Bool = true) -> Binding<Bool> {
        store.binding(page: "gallery", id: id, byDefault: byDefault)
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SpecimenLayout.panel(title, content: content)
    }

    private func caption(_ text: String) -> some View { SpecimenLayout.caption(text) }

    private let halfCanvas = SpecimenLayout.halfCanvas

    private func pairs(_ items: [(String, AnyView)]) -> some View { SpecimenLayout.pairs(items) }
}
