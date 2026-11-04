import AppKit
import ReinsCore
import SwiftUI

/// What the shell shows for the Limits page in place of a tab's title and hints.
enum LimitsPage {
    static let title = "Limits"
    static let hints = [KeyHint(keys: "\u{2318}R", label: "Refresh")]
}

/// The Limits page (spec, Interface: Limits, layout H), in the content area when the sidebar entry, its tiles or `⌘L` open it.
/// Every window of every CLI is a tile in the list on the left with its ruler and share left, and Gemini CLI (or any CLI
/// without a reading) is a tile with its state; the selected one is on the right: its name, the share left in `display`, a
/// ruler and three facts, with the reading's source under them. The window with the least left is selected first. Only
/// files already on this Mac are read.
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
            Button { Task { await model.readOnce() } } label: {
                HStack(spacing: Space.s6) {
                    ReinsIcon(.refresh)
                    Text("Refresh")
                }
            }
            .buttonStyle(.reins(.normal))
            .keyboardShortcut("r", modifiers: .command)
            FilterChip("Show windows not in use", isOn: model.showInactive) { model.showInactive.toggle() }
            Spacer(minLength: 0)
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
            HStack(alignment: .top, spacing: Rhythm.listDetail) {
                VStack(spacing: Rhythm.tiles) {
                    ForEach(entries) { entry in
                        LimitsEntryTile(entry: entry, limits: model.limits(for: entry.cli), isSelected: entry.id == selected, now: now) {
                            model.selectedID = entry.id
                        }
                    }
                }
                .frame(width: Metrics.limitsListWidth)
                LimitsSelection(entry: entries.first { $0.id == selected }, now: now)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One tile of the list: a window, or a CLI that lists none.
private struct LimitsEntryTile: View {
    let entry: LimitsWording.Entry
    let limits: CLILimits?
    let isSelected: Bool
    let now: Date
    let select: () -> Void

    var body: some View {
        let name = LimitsWording.cliName(entry.cli)
        if let window = entry.window {
            let current = window.isCurrent(at: now)
            let left = LimitsWording.shareLeft(window)
            let tone = current ? LimitsWording.tone(window).tile : .normal
            LimitWindowTile(
                cli: entry.cli, title: LimitsWording.name(window), subtitle: LimitsWording.entryLine(window, cli: entry.cli, now: now),
                meter: current ? .share(Double(left) / 100, fill: tone.barFill ?? entry.cli.fill) : .unknown,
                value: current ? "\(left)%" : "unknown", valueTone: tone.figureTone, selected: isSelected, onActivate: select
            ) {
                if !window.active { Tag("not in use") }
            }
        } else {
            let note = limits.map(LimitsWording.entryNote) ?? (title: "Reading", body: "Looking at the files on this Mac.")
            LimitWindowTile(cli: entry.cli, title: name, subtitle: note.title, meter: .none, value: "\u{2014}",
                            selected: isSelected, onActivate: select)
        }
    }
}

/// The detail card: the selected window, or the state of a CLI that has none.
private struct LimitsSelection: View {
    @Environment(LimitsModel.self) private var model
    let entry: LimitsWording.Entry?
    let now: Date

    var body: some View {
        if let entry, let limits = model.limits(for: entry.cli) {
            ContentCard {
                VStack(alignment: .leading, spacing: Space.s16) {
                    HStack(spacing: Space.s8) {
                        CLIMark(entry.cli, size: .medium)
                        Text(title(entry)).reinsText(.title, tone: .primary).lineLimit(1)
                        if let window = entry.window, !window.active { Tag("not in use") }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    if let window = entry.window { WindowFacts(window: window, limits: limits, now: now) } else { StateNote(limits: limits) }
                }
            }
        }
    }

    /// "Codex · Weekly"; the CLI's name alone when it lists no window.
    private func title(_ entry: LimitsWording.Entry) -> String {
        let cli = LimitsWording.cliName(entry.cli)
        return entry.window.map { "\(cli) \u{00B7} \(LimitsWording.name($0))" } ?? cli
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
        let reset = LimitsWording.resetFact(window, now: now)
        VStack(alignment: .leading, spacing: Space.s16) {
            LimitFigure(left: current ? left : nil, tone: tone)
            Ruler(share: current ? Double(left) / 100 : nil, fill: tone.barFill ?? limits.cli.fill, height: Metrics.rulerDetailHeight)
            HStack(alignment: .top, spacing: Rhythm.tiles) {
                FactTile(reset.label, value: reset.value)
                FactTile(current ? "Resets at" : "Reset at", value: LimitsWording.resetsAt(window, now: now))
                if case .measured(let at, _) = limits.state {
                    FactTile("Reading", value: LimitsWording.readAge(at: at, now: now),
                             tone: LimitsWording.isStale(at: at, now: now) ? .warn : .primary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            source
        }
    }

    /// Where the reading comes from, and for Claude Code (whose cache only moves when it fetches usage) how to refresh it.
    @ViewBuilder
    private var source: some View {
        if let source = LimitsWording.source(limits.cli) {
            HStack(spacing: Space.s12) {
                Text(source.title).reinsText(.caption, tone: .secondary).help(source.body)
                if limits.cli == .claude { CopyUsageButton() }
            }
        }
    }
}

/// A CLI with no window to show: its state as one line, and `Copy /usage` when Claude Code has never fetched usage.
private struct StateNote: View {
    let limits: CLILimits

    var body: some View {
        let note = LimitsWording.entryNote(limits)
        let icon: ReinsGlyph = limits.state == .notMeasurable || limits.state == .unreadable ? .warning : .info
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(alignment: .top, spacing: Space.s8) {
                ReinsIcon(icon, ink: TextTone.secondary.color).padding(.top, Space.s2)
                (Text("\(note.title). ").reinsText(.bodyStrong, tone: .primary) + Text(note.body).reinsText(.body, tone: .secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if limits.cli == .claude && limits.state == .notRecorded { CopyUsageButton() }
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
