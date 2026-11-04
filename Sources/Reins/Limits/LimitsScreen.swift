import AppKit
import ReinsCore
import SwiftUI

/// What the shell shows for the Limits page in place of a tab's title and hints.
enum LimitsPage {
    static let title = "Limits"
    static let hints = [KeyHint(keys: "\u{2318}R", label: "Refresh")]
}

/// The Limits page (spec, Interface: Limits, layout H), in the content area when the sidebar block or `⌘L` opens it.
/// Every window of every CLI is a row on the left with its ruler and share left, and Gemini CLI (or any CLI without a
/// reading) is a row with its state; the selected one is on the right: its name, the share left in `display`, a ruler and
/// three facts. The window with the least left is selected first. Only files already on this Mac are read.
struct LimitsScreen: View {
    @Environment(LimitsModel.self) private var model

    var body: some View {
        TimelineView(.everyMinute) { context in
            PageLayout {
                tools
            } content: {
                content(now: context.date).modifier(ShotFit())
            }
        }
    }

    private var tools: some View {
        HStack(spacing: Rhythm.tools) {
            FilterChip("Show windows not in use", isOn: model.showInactive) { model.showInactive.toggle() }
            Spacer(minLength: 0)
            Button { Task { await model.readOnce() } } label: {
                HStack(spacing: Space.s6) {
                    ReinsIcon(.refresh)
                    Text("Refresh")
                }
            }
            .buttonStyle(.reins(.normal))
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if model.results.isEmpty {
            if let failure = model.failure {
                Banner(.error, message: "Could not read the limits.", detail: failure, actionTitle: "Try again") {
                    Task { await model.readOnce() }
                }
            } else {
                EmptyState("Reading limits\u{2026}", message: "Only files already on this Mac are read.")
            }
        } else {
            let entries = LimitsWording.entries(model.results, showInactive: model.showInactive)
            let selected = model.selection(in: entries, now: now)
            HStack(alignment: .top, spacing: Rhythm.cards) {
                LimitsList(entries: entries, selected: selected, now: now) { model.selectedID = $0 }
                    .frame(maxWidth: .infinity)
                LimitsSelection(entry: entries.first { $0.id == selected }, now: now)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The left card: one section per CLI, a row per window.
private struct LimitsList: View {
    @Environment(LimitsModel.self) private var model
    let entries: [LimitsWording.Entry]
    let selected: String?
    let now: Date
    let select: (String) -> Void

    var body: some View {
        GroupedList {
            CardHeader("Windows", count: entries.filter { $0.window != nil }.count)
            ForEach(LimitsCLI.allCases, id: \.self) { cli in
                let rows = entries.filter { $0.cli == cli }
                if !rows.isEmpty {
                    SectionRow(LimitsWording.cliName(cli))
                    ForEach(rows) { entry in
                        LimitsEntryRow(entry: entry, limits: model.limits(for: cli), isSelected: entry.id == selected, now: now) {
                            select(entry.id)
                        }
                    }
                }
            }
        }
    }
}

private struct LimitsEntryRow: View {
    let entry: LimitsWording.Entry
    let limits: CLILimits?
    let isSelected: Bool
    let now: Date
    let select: () -> Void

    var body: some View {
        Row(selected: isSelected, onActivate: select) {
            if let window = entry.window {
                RowText(LimitsWording.name(window), subtitle: LimitsWording.resets(window, now: now)) {
                    if !window.active { Tag("not in use") }
                }
            } else {
                RowText(note.title)
            }
        }
        .cells { cell }
        .accessibilityLabel("\(LimitsWording.cliName(entry.cli)), \(entry.window.map(LimitsWording.name) ?? note.title)")
    }

    private var note: (title: String, body: String) {
        limits.map(LimitsWording.entryNote) ?? (title: "Reading", body: "Looking at the files on this Mac.")
    }

    @ViewBuilder
    private var cell: some View {
        if let window = entry.window, window.isCurrent(at: now) {
            let tone = LimitsWording.tone(window).tile
            LimitShareCell(
                share: Double(LimitsWording.shareLeft(window)) / 100, text: "\(LimitsWording.shareLeft(window))%",
                fill: tone.barFill ?? entry.cli.fill, tone: tone.figureTone
            )
        } else {
            // A passed reset, or no reading at all: nothing is known, so the ruler is the dashed outline.
            LimitShareCell(share: nil, text: "\u{2014}", fill: entry.cli.fill)
        }
    }
}

/// The right card: the selected window, or the state of a CLI that has none.
private struct LimitsSelection: View {
    @Environment(LimitsModel.self) private var model
    let entry: LimitsWording.Entry?
    let now: Date

    var body: some View {
        if let entry, let limits = model.limits(for: entry.cli) {
            GroupedList {
                CardHeader(entry.window.map(LimitsWording.name) ?? LimitsWording.cliName(entry.cli), detail: subtitle(limits, hasWindow: entry.window != nil))
                VStack(alignment: .leading, spacing: 0) {
                    if let window = entry.window { WindowFacts(window: window, limits: limits, now: now) } else { StateFacts(limits: limits) }
                }
                .padding(.horizontal, Metrics.rowHorizontalPadding)
                .padding(.bottom, Space.s8)
                .groupedListPart(.plain)
            }
        }
    }

    /// "Codex · Plus" under a window's name; the plan alone under a CLI's.
    private func subtitle(_ limits: CLILimits, hasWindow: Bool) -> String? {
        let plan = limits.plan.map(LimitsWording.planName)
        guard hasWindow else { return plan }
        return ([LimitsWording.cliName(limits.cli)] + [plan].compactMap { $0 }).joined(separator: " \u{00B7} ")
    }
}

private struct WindowFacts: View {
    let window: LimitWindow
    let limits: CLILimits
    let now: Date

    var body: some View {
        let current = window.isCurrent(at: now)
        let tone = current ? LimitsWording.tone(window).tile : .normal
        let left = LimitsWording.shareLeft(window)
        VStack(alignment: .leading, spacing: Space.s16) {
            LimitFigure(left: current ? left : nil, tone: tone)
            Ruler(share: current ? Double(left) / 100 : nil, fill: tone.barFill ?? limits.cli.fill)
            HStack(alignment: .top, spacing: Rhythm.tiles) {
                FactTile("Resets in", value: LimitsWording.resetsIn(window, now: now) ?? "passed", note: current ? nil : "no newer reading")
                FactTile(current ? "Resets at" : "Reset at", value: LimitsWording.resetsAt(window, now: now))
                reading
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var reading: some View {
        if case .measured(let at, _) = limits.state {
            let age = LimitsWording.readAge(at: at, now: now)
            let tone: TextTone = LimitsWording.isStale(at: at, now: now) ? .warn : .primary
            let source = LimitsWording.source(limits.cli)?.title
            if limits.cli == .claude {
                FactTile("Reading", value: age, tone: tone, note: source) { CopyUsageButton() }
            } else {
                FactTile("Reading", value: age, tone: tone, note: source)
            }
        }
    }
}

private struct StateFacts: View {
    let limits: CLILimits

    var body: some View {
        let note = LimitsWording.entryNote(limits)
        let icon: ReinsGlyph = limits.state == .notMeasurable || limits.state == .unreadable ? .warning : .info
        if limits.cli == .claude && limits.state == .notRecorded {
            EmptyState(note.title, message: note.body, icon: icon) { CopyUsageButton() }
        } else {
            EmptyState(note.title, message: note.body, icon: icon)
        }
    }
}

/// Copies `/usage` for Claude Code, whose cache only moves when it fetches usage itself.
private struct CopyUsageButton: View {
    var body: some View {
        Button { LimitsClipboard.copyUsageCommand() } label: {
            HStack(spacing: Space.s6) {
                ReinsIcon(.copy)
                Text("Copy \(LimitsWording.copyHint)")
            }
        }
        .buttonStyle(.reins(.normal))
    }
}

/// Copies text only. Reins never runs the command (S-R4).
enum LimitsClipboard {
    @MainActor
    static func copyUsageCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(LimitsWording.copyHint, forType: .string)
    }
}
