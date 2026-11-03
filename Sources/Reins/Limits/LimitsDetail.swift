import AppKit
import ReinsCore
import SwiftUI

/// What the sidebar block opens: a card for Claude Code and one for Codex side by side, Gemini CLI under them. Each
/// window is a tile; the tightest current one leads. Only reads files that are already on this Mac (spec, Limits).
struct LimitsDetail: View {
    @Environment(LimitsModel.self) private var model

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: Space.s16) {
                tools
                HStack(alignment: .top, spacing: Space.s16) {
                    card(.claude, now: context.date)
                    card(.codex, now: context.date)
                }
                card(.gemini, now: context.date)
            }
            .padding(Space.s16)
            .frame(width: Metrics.limitsDetailWidth)
            .pageBackground()
        }
    }

    private var tools: some View {
        HStack(spacing: Space.s8) {
            Text("Limits").reinsText(.title, tone: .primary)
            Spacer(minLength: Space.s8)
            FilterChip("Show windows not in use", isOn: model.showInactive) { model.showInactive.toggle() }
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
    private func card(_ cli: LimitsCLI, now: Date) -> some View {
        let limits = model.limits(for: cli)
        LimitCard(cli, title: LimitsWording.cliName(cli), plan: limits?.plan.map(LimitsWording.planName)) {
            if let limits, case .measured(let at, _) = limits.state { LimitsReadingAge(at: at, now: now) }
        } trailing: {
            if let limits, case .measured(let at, _) = limits.state, LimitsWording.source(cli) != nil {
                LimitsSourceButton(cli: cli, at: at, now: now)
            }
        } content: {
            if let limits { tiles(limits, now: now) } else {
                LimitNoteTile(title: model.failure == nil ? "Reading" : "Unavailable", text: model.failure ?? "Looking at the files on this Mac.")
            }
        }
    }

    @ViewBuilder
    private func tiles(_ limits: CLILimits, now: Date) -> some View {
        if case .measured(_, let windows) = limits.state {
            let shown = LimitsWording.visible(windows, showInactive: model.showInactive)
            let lead = LimitsWording.tightest(windows, now: now)
            if shown.isEmpty {
                LimitNoteTile(title: "No current window", text: "\(LimitsWording.cliName(limits.cli)) records no limit that applies right now.")
            }
            ForEach(shown, id: \.id) { window in
                LimitTile(
                    cli: limits.cli,
                    title: LimitsWording.name(window),
                    detail: LimitsWording.resets(window, now: now),
                    tags: tags(window, now: now),
                    reading: window.isCurrent(at: now) ? .share(left: LimitsWording.shareLeft(window), tone: LimitsWording.tone(window).tile) : .unknown,
                    isLead: lead?.id == window.id
                )
            }
        } else if let note = LimitsWording.stateNote(limits) {
            LimitNoteTile(title: note.title, text: note.body, isWarn: limits.state == .notMeasurable || limits.state == .unreadable, action: copyAction(limits))
        }
    }

    private func tags(_ window: LimitWindow, now: Date) -> [LimitTileTag] {
        var tags: [LimitTileTag] = []
        if !window.active { tags.append(LimitTileTag(text: "not in use")) }
        if !window.isCurrent(at: now) { tags.append(LimitTileTag(text: "reset passed", tone: .warn, icon: .clock)) }
        return tags
    }

    private func copyAction(_ limits: CLILimits) -> (title: String, icon: ReinsGlyph, run: () -> Void)? {
        guard limits.cli == .claude, limits.state == .notRecorded else { return nil }
        return ("Copy \(LimitsWording.copyHint)", .copy, { LimitsClipboard.copyUsageCommand() })
    }
}

/// "read 4 min ago", as a warn tag once the reading is stale.
private struct LimitsReadingAge: View {
    let at: Date
    let now: Date

    var body: some View {
        let age = LimitsWording.readAge(at: at, now: now)
        if LimitsWording.isStale(at: at, now: now) {
            Tag(age, tone: .warn, icon: .clock)
        } else {
            Text(age).reinsText(.caption, tone: .secondary)
        }
    }
}

/// The info button: where this CLI's reading comes from, and for Claude Code how to refresh it.
private struct LimitsSourceButton: View {
    let cli: LimitsCLI
    let at: Date
    let now: Date
    @State private var showSource = false

    var body: some View {
        if let source = LimitsWording.source(cli) {
            Button { showSource.toggle() } label: { ReinsIcon(.info) }
                .buttonStyle(.reins(.plainIcon))
                .accessibilityLabel("Where this reading comes from")
                .popover(isPresented: $showSource, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: Space.s8) {
                        Text(source.title).reinsText(.bodyStrong, tone: .primary)
                        Text(source.body).reinsText(.caption, tone: .secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Space.s8) {
                            if cli == .claude {
                                Button { LimitsClipboard.copyUsageCommand() } label: {
                                    HStack(spacing: Space.s6) {
                                        ReinsIcon(.copy)
                                        Text("Copy \(LimitsWording.copyHint)")
                                    }
                                }
                                .buttonStyle(.reins(.normal))
                            }
                            Text(LimitsWording.readAge(at: at, now: now)).reinsText(.caption, tone: .secondary)
                        }
                    }
                    .padding(Space.s16)
                    .frame(width: Metrics.limitSourceWidth, alignment: .leading)
                }
        }
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
