import AppKit
import SwiftUI

/// The Loadout tab: loading, failed, or the toolbar over the matrix table.
struct LoadoutScreen: View {
    let model: LoadoutModel
    @Environment(ShellModel.self) private var shell

    var body: some View {
        content
            // Mounted at launch (the shell keeps every tab alive), so the sidebar count is there before the first visit.
            .task {
                model.shell = shell
                model.start()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if let view = model.view(), let data = model.data {
            VStack(spacing: 0) {
                LoadoutToolbar(model: model, view: view, scopes: data.scopes)
                LoadoutTable(model: model, view: view, data: data)
            }
        } else if let failure = model.readFailure {
            PageLayout {
                Banner(.error, message: "Could not read what is installed.", detail: failure, actionTitle: "Retry", action: model.retry)
            }
        } else {
            PageLayout {
                EmptyState("Reading skills, agents and hooks\u{2026}")
            }
        }
    }
}
