import SwiftUI

/// The Limits entry in the sidebar list, after the tabs (owner, 2026-11-04): active while the page is open, with a warn
/// clock after the title when a reading is older than six hours.
struct LimitsSidebarItem: View {
    @Environment(LimitsModel.self) private var model
    @Environment(ShellModel.self) private var shell

    var body: some View {
        TimelineView(.everyMinute) { context in
            SidebarItem(title: LimitsPage.title, icon: .limits, isActive: shell.isLimitsOpen) {
                if LimitsSidebarBlock.hasStaleReading(model.results, now: context.date) { StaleMark() }
            } select: {
                shell.openLimits()
            }
        }
    }
}

/// The Limits tiles above the sidebar footer, on every tab: one tile per CLI with the share left of its tightest window.
/// Clicking them (or the Limits entry, or `⌘L`) opens the Limits page in the content area. Reads run while the window is
/// active (launch, each time it becomes active, then every minute).
struct LimitsSidebarBlock: View {
    @Environment(LimitsModel.self) private var model
    @Environment(ShellModel.self) private var shell
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.everyMinute) { context in
            Button { shell.openLimits() } label: {
                VStack(alignment: .leading, spacing: Space.s6) {
                    ForEach(CoreLimitsCLI.allCases, id: \.self) { cli in
                        tile(cli, now: context.date)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .spaceVibeFocusable(cornerRadius: Metrics.controlRadius)
            .accessibilityHint("Opens Limits")
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            await model.run()
        }
    }

    static func hasStaleReading(_ results: [CoreLimitsEntry], now: Date) -> Bool {
        results.contains { limits in
            limits.reading.map { LimitsWording.isStale(at: $0.at, now: now) } ?? false
        }
    }

    @ViewBuilder
    private func tile(_ cli: CoreLimitsCLI, now: Date) -> some View {
        let name = LimitsWording.cliName(cli)
        if let limits = model.limits(for: cli) {
            switch LimitsWording.summary(limits, now: now) {
            case .share(let left, let tone, let stale):
                LimitSidebarTile(cli: cli, name: name, value: "\(left)% left\(stale ? " · old" : "")", tone: tone.tile)
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
