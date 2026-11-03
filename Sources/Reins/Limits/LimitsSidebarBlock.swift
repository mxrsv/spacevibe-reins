import ReinsCore
import SwiftUI

/// The Limits block above the sidebar footer, on every tab: one tile per CLI with the share left of its tightest window.
/// Clicking it (or `⌘L`) opens the detail beside the sidebar. Reads run while the window is active (launch, each time it
/// becomes active, then every minute).
struct LimitsSidebarBlock: View {
    @Environment(LimitsModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TimelineView(.everyMinute) { context in
            Button { model.isDetailOpen.toggle() } label: {
                VStack(alignment: .leading, spacing: Space.s6) {
                    HStack(spacing: Space.s6) {
                        Image(systemName: "gauge.with.dots.needle.33percent").imageScale(.small).accessibilityHidden(true)
                        Text("Limits")
                        if hasStaleReading(now: context.date) { StaleMark() }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").imageScale(.small).accessibilityHidden(true)
                    }
                    .reinsText(.bodyStrong, tone: .primary)
                    .padding(.horizontal, Space.s4)
                    ForEach(LimitsCLI.allCases, id: \.self) { cli in
                        tile(cli, now: context.date)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .reinsFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityLabel("Limits")
            .accessibilityHint("Shows every usage limit window")
            .popover(isPresented: $model.isDetailOpen, arrowEdge: .trailing) { LimitsDetail() }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await model.run()
        }
    }

    private func hasStaleReading(now: Date) -> Bool {
        model.results.contains { limits in
            if case .measured(let at, _) = limits.state { return LimitsWording.isStale(at: at, now: now) }
            return false
        }
    }

    @ViewBuilder
    private func tile(_ cli: LimitsCLI, now: Date) -> some View {
        let name = LimitsWording.cliName(cli)
        if let limits = model.limits(for: cli) {
            switch LimitsWording.summary(limits, now: now) {
            case .share(let left, let tone, _):
                LimitSidebarTile(cli: cli, name: name, value: "\(left)% left", tone: tone.tile, fraction: Double(left) / 100)
            case .unknown:
                LimitSidebarTile(cli: cli, name: name, value: "unknown", isMuted: true)
            case .state(let text):
                LimitSidebarTile(cli: cli, name: name, value: text, isMuted: true)
            }
        } else {
            LimitSidebarTile(cli: cli, name: name, value: model.failure == nil ? "reading" : "unavailable", isMuted: true)
        }
    }
}

extension LimitsWording.Tone {
    /// The component's own tone type, so `Components/` does not import the wording.
    var tile: LimitTone {
        switch self {
        case .normal: .normal
        case .low: .low
        case .out: .out
        }
    }
}
