import AppKit
import ReinsCore
import SwiftUI

/// The Rules tab: loading, failed, or the toolbar over the grid, the rule list and the Codex group, with the grid
/// confirmation over them.
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
                            RulesGrid(model: model, snapshot: snapshot)
                            RulesList(model: model, snapshot: snapshot).padding(.top, Rhythm.regions)
                            RulesAddRow(model: model).id(Self.addRowID).padding(.top, Rhythm.laneCards)
                            RulesCodexGroup(snapshot: snapshot).padding(.top, Rhythm.regions)
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

    @ViewBuilder
    private func banners(_ snapshot: RulesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            if let failure = model.failure {
                Banner(.error, message: "The last read failed, so this may be out of date.", detail: failure, actionTitle: "Retry", action: model.retry)
            }
            ForEach(snapshot.problems, id: \.self) { problem in
                Banner(.error, message: problem, detail: "The grid and the rules below are read-only until the file is valid.")
            }
            if snapshot.codex.model == .both {
                Banner(.warn, message: snapshot.codex.warnings.first ?? "Both Codex permission models are set.", detail: "Reins shows both and writes neither.")
            }
        }
        .padding(.bottom, snapshot.problems.isEmpty && model.failure == nil && snapshot.codex.model != .both ? 0 : Rhythm.cards)
    }
}
