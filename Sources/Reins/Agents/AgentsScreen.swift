import ReinsCore
import SwiftUI

/// The Agents page (spec `docs/specs/2026-11-05-reins-agents.md`, Interface): one card per agent, stacked, and the one open
/// panel on the right, pushing the cards aside. The cards never get narrower than 440 pt; the page's minimum width grows
/// with the panel instead. The review dialog and the copy confirmation are the only things that block the window.
struct AgentsScreen: View {
    @Bindable var model: AgentsModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            cards.frame(minWidth: Metrics.agentCardsMinWidth, maxWidth: .infinity)
            if let open = model.open {
                AgentsPanelHost(model: model, open: open)
            }
        }
        .frame(minWidth: InspectorWidth.minimumContent(panel: model.open.map { panelWidth($0) }))
        .overlay { dialogs }
        .task { model.start() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
    }

    private func panelWidth(_ open: OpenPanel) -> CGFloat {
        open.panel == .advanced ? model.advancedWidth : model.panelWidth
    }

    @ViewBuilder
    private var cards: some View {
        if let overview = model.overview {
            PageLayout {
                VStack(alignment: .leading, spacing: Rhythm.cards) {
                    if let failure = model.failure { Banner(.error, message: "Could not read the agents' settings", detail: failure) }
                    ForEach(AgentKind.allCases) { agent in
                        AgentCard(agent: agent, overview: overview, openPanel: model.open?.agent == agent ? model.open?.panel : nil) { panel in
                            model.toggle(OpenPanel(agent: agent, panel: panel))
                        }
                    }
                }
            }
        } else if let failure = model.failure {
            PageLayout { EmptyState("Could not read the agents' settings", message: failure, icon: .warning) }
        } else {
            PageLayout { EmptyState("Reading the agents' settings\u{2026}", icon: .refresh) }
        }
    }

    @ViewBuilder
    private var dialogs: some View {
        if model.isReviewing, let context = model.saveContext {
            AgentsReviewDialog(model: model, context: context)
        } else if let hook = model.pendingCopy {
            ConfirmationDialog(
                "Copy this hook to \(hook.cli == .claude ? "Codex" : "Claude Code")?",
                message: AgentsHookWording.copyWarning(hook),
                cancel: { model.pendingCopy = nil }
            ) {
                Button("Cancel") { model.pendingCopy = nil }.buttonStyle(.reins(.normal))
                Button("Copy") { model.confirmCopy() }.buttonStyle(.reins(.primary)).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The review before a save (spec, Draft and save): each change with its verb and verdict tag, the scope, the file or
/// files, the copy note, and a warn note for each risky value.
struct AgentsReviewDialog: View {
    let model: AgentsModel
    let context: AgentsSavePlan.Context

    var body: some View {
        ConfirmationDialog(
            AgentsReview.title(model.draft, context), message: AgentsReview.scopeLine(context), width: Metrics.wideDialogWidth,
            canCancel: !model.isSaving, cancel: { model.isReviewing = false }
        ) {
            InsetBox {
                ForEach(model.draft.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                        Text(item.verb.rawValue).reinsText(.label, tone: .tertiary)
                        if let tag = item.tag { Tag(tag, tone: item.tagTone) }
                        Text(item.text).reinsText(.code, tone: .primary).lineLimit(2).truncationMode(.middle)
                    }
                }
            }
            ForEach(AgentsSavePlan.files(model.draft, context), id: \.self) { file in
                HStack(spacing: Space.s6) {
                    PageIcon(.file, size: .inline).foregroundStyle(TextTone.tertiary.color)
                    Text(file).reinsText(.code, tone: .secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            ForEach(AgentsReview.warnings(model.draft), id: \.self) { WarningNote(text: $0) }
            Text(AgentsReview.copyNote).reinsText(.caption, tone: .tertiary)
        } actions: {
            Button("Cancel") { model.isReviewing = false }.buttonStyle(.reins(.normal)).disabled(model.isSaving)
            Button { model.save() } label: { ButtonLabel("Save", icon: .check) }
                .buttonStyle(.reins(.primary))
                .controlLoading(model.isSaving)
                .keyboardShortcut(.defaultAction)
        }
    }
}
