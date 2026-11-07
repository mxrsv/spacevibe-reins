import AppKit
import SwiftUI

/// The Rules tab: loading, failed, or the toolbar over one CLI's page. Claude Code: the grid, the rule list and the add row,
/// with the grid confirmation over them. Codex: its read-only page. Each page opens with a line about the other CLI.
struct RulesScreen: View {
    let model: RulesModel
    @Environment(ShellModel.self) private var shell

    var body: some View {
        ZStack {
            content
                // Not `.disabled`: that would dim every hidden row action behind the confirmation.
                .allowsHitTesting(model.pending == nil)
                .accessibilityHidden(model.pending != nil)
            if let pending = model.pending {
                RulesConfirmation(pending: pending, cancel: model.cancelPending, confirm: model.confirmPending)
                    .transition(.opacity)
            }
        }
        // Mounted at launch (the shell keeps every tab alive), so the sidebar count is there before the first visit.
        .task {
            model.shell = shell
            model.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.snapshot {
            ScrollViewReader { proxy in
                PageLayout(
                    tools: { RulesToolbar(model: model, snapshot: snapshot) },
                    content: {
                        VStack(alignment: .leading, spacing: 0) {
                            banners(snapshot)
                            summary(snapshot).padding(.bottom, Rhythm.cards)
                            if model.cli == .claude {
                                RulesGrid(model: model, snapshot: snapshot)
                                RulesList(model: model, snapshot: snapshot).padding(.top, Rhythm.regions)
                                RulesAddRow(model: model).id(Self.addRowID).padding(.top, Rhythm.laneCards)
                            } else {
                                RulesCodexPage(model: model, snapshot: snapshot)
                            }
                        }
                        .modifier(ShotFit())
                    }
                )
                .onChange(of: model.addFocusToken) { _, _ in withAnimation { proxy.scrollTo(Self.addRowID, anchor: .center) } }
            }
        } else if let failure = model.failure {
            PageLayout {
                Banner(.error, message: "Could not read the permissions.", detail: failure, actionTitle: "Retry", action: model.retry)
            }
        } else {
            PageLayout {
                EmptyState("Reading permissions\u{2026}")
            }
        }
    }

    private static let addRowID = "rules-add-row"

    /// What the banners say besides the failed read, in order. On the Codex page a warning the core adds (an unreadable
    /// `config.toml`, skipped lines, an unreadable rules folder) is one more banner next to the two-models one.
    private func notices(_ snapshot: RulesSnapshot) -> [String] {
        if model.cli == .claude {
            return snapshot.globalNotReadable && snapshot.selection.dir != nil ? [RulesWording.globalNotReadable] : []
        }
        return RulesWording.codexNotices(snapshot.codex)
    }

    private func hasBanner(_ snapshot: RulesSnapshot) -> Bool {
        model.failure != nil || (model.cli == .claude ? !snapshot.problems.isEmpty : snapshot.codex.model == .both)
            || !notices(snapshot).isEmpty
    }

    /// How the other CLI stands, so a page that shows one CLI never hides the other.
    @ViewBuilder
    private func summary(_ snapshot: RulesSnapshot) -> some View {
        if model.cli == .claude {
            let codex = CodexWording.status(snapshot.codex)
            CLISummaryBar(cli: .codex, message: codex.sentence, warn: codex.tone == .warn, actionTitle: "Open Codex") { model.selectCLI(.codex) }
        } else {
            let invalid = !snapshot.problems.isEmpty
            CLISummaryBar(
                cli: .claude,
                message: invalid ? "The settings file here is not valid JSON" : RulesWording.summary(snapshot.grid, ruleCount: snapshot.rules.count),
                warn: invalid,
                actionTitle: "Open Claude Code"
            ) { model.selectCLI(.claude) }
        }
    }

    @ViewBuilder
    private func banners(_ snapshot: RulesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            if let failure = model.failure {
                Banner(.error, message: "The last read failed, so this may be out of date.", detail: failure, actionTitle: "Retry", action: model.retry)
            }
            if model.cli == .claude {
                ForEach(snapshot.problems, id: \.self) { problem in
                    Banner(.error, message: problem, detail: "The grid and the rules below are read-only until the file is valid.")
                }
            } else if snapshot.codex.model == .both {
                Banner(.warn, message: snapshot.codex.warnings.first ?? "Both Codex permission models are set.", detail: "SpaceVibe shows both and writes neither.")
            }
            ForEach(notices(snapshot), id: \.self) { Banner(.warn, message: $0) }
        }
        .padding(.bottom, hasBanner(snapshot) ? Rhythm.cards : 0)
    }
}
