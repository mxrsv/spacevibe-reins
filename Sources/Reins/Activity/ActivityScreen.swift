import SwiftUI

/// The Activity tab: loading, failed, or the two lanes and the file history, with the Stop confirmation over them.
struct ActivityScreen: View {
    let model: ActivityModel
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let isActive = shell.activeID == ActivityTab.tabID
        ZStack {
            content
                // Not `.disabled`: that would show every hidden Stop button dimmed behind the confirmation.
                .allowsHitTesting(model.pendingStop == nil)
                .accessibilityHidden(model.pendingStop != nil)
            if let session = model.pendingStop {
                ActivityStopConfirmation(title: session.title, isStopping: model.isStopping, cancel: model.cancelStop, confirm: model.confirmStop)
                    .transition(.opacity)
            }
        }
        // Reads while this tab shows, and once at launch for the sidebar badge; SwiftUI cancels the task on a tab switch.
        .task(id: isActive) { await model.run(active: isActive) }
    }

    @ViewBuilder
    private var content: some View {
        if let report = model.report {
            let now = Date()
            let elapsedMs = model.readAt.map { max(0, now.timeIntervalSince($0) * 1000) } ?? 0
            PageLayout {
                VStack(alignment: .leading, spacing: 0) {
                    if let failure = model.failure {
                        Banner(.error, message: "The last read failed, so this may be out of date.", detail: failure, actionTitle: "Try again", action: model.retry)
                            .padding(.bottom, Rhythm.cards)
                    }
                    HStack(alignment: .top, spacing: Rhythm.cards) {
                        ForEach(CoreCLI.allCases, id: \.rawValue) { cli in
                            ActivityLane(cli: cli, report: report, now: now, elapsedMs: elapsedMs, revealActions: model.revealRowActions) { model.requestStop($0) }
                        }
                    }
                    NoteRegion(
                        title: "Cannot be measured",
                        columns: CoreCLI.allCases.map { NoteRegion.Column(core: $0, notes: ActivityRows.limits(report, cli: $0).map(\.text)) },
                        shared: [ActivityRows.costLimit]
                    )
                    .padding(.top, Rhythm.cards)
                    ActivityFileHistory(files: report.files, now: now)
                        .padding(.top, Rhythm.regions)
                }
                .modifier(ShotFit())
            }
        } else if let failure = model.failure {
            PageLayout {
                EmptyState("Could not read the session logs.", message: failure, icon: .warning) {
                    Button("Try again", action: model.retry).buttonStyle(.reins(.normal))
                }
            }
        } else {
            PageLayout {
                EmptyState("Reading logs\u{2026}", message: "The first read of a long history can take a while. Nothing is changed.") {
                    LoadingMark()
                }
            }
        }
    }
}

/// A spinner in the app; a static mark in headless screenshots, where AppKit-backed controls do not draw.
private struct LoadingMark: View {
    @Environment(\.isShotRendering) private var isShotRendering

    var body: some View {
        if isShotRendering {
            ReinsIcon(.refresh).foregroundStyle(TextTone.tertiary.color)
        } else {
            ProgressView().controlSize(.small)
        }
    }
}
