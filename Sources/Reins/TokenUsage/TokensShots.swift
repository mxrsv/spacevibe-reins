import AppKit
import Foundation
import ReinsCore
import SwiftUI

/// Headless screenshots of the real Tokens screen, selected by `REINS_SHOT_SCREEN=tokens` with `REINS_TEST=1` and
/// `REINS_SHOT_DIR`, as the CI's screenshot step sets them:
///
///     REINS_SHOT_SCREEN=tokens scripts/dev-fixture.sh --shots <dir>
///
/// The ledger is scanned from the synthetic HOME before any frame is drawn (`ImageRenderer` draws one frame and runs no
/// `.task`); every shot shows that real result, scoped or with a control set. The two states without data are an empty
/// result and the first scan; the moved-aside state reuses the real result with the banner's path set. Nothing outside the
/// synthetic HOME is read or written: `Roots.resolve` refuses a root under the real home when `REINS_TEST=1`.
///
/// On GitHub Actions a few shots are also printed to the log as base64 JPEG between `REINS-SHOT-BEGIN <name>` and
/// `REINS-SHOT-END`, because a cloud session may be unable to download the run's artifacts.
@MainActor
enum TokensShots {
    static func isRequested(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["REINS_TEST"] == "1" && environment["REINS_SHOT_SCREEN"] == "tokens"
    }

    private struct ShotFailure: LocalizedError {
        let errorDescription: String?
    }

    static func run(into directory: URL) throws {
        let env = AppEnvironment.live(toasts: ToastCenter(announce: false))
        guard let roots = env.roots else { throw ShotFailure(errorDescription: env.startupProblem ?? "no roots") }
        let loader = TokensModel(env: env)
        let result = try scanBeforeRendering(loader)
        let now = Date()

        for choice in [AppearanceChoice.dark, .light] {
            func shot(_ name: String, echo: Bool = false, _ configure: (TokensModel) -> Void = { _ in }) throws {
                let model = TokensModel(env: env)
                model.preview(result: result, now: now)
                configure(model)
                try write(screen(model, env: env, choice: choice), name: "tokens-\(name)", choice: choice, to: directory, echo: echo)
            }
            try shot("default", echo: true)
            try shot("tokens") { $0.measure = .tokens }
            try shot("new-only") { $0.measure = .fresh }
            try shot("price", echo: choice == .light) { $0.isPriceTableOpen = true }
            try shot("scoped", echo: choice == .dark) { model in
                guard let board = model.board else { return }
                model.selectedID = board.buckets.dropFirst().first { !$0.both.isEmpty }?.id
                if let top = model.board?.models(.claude).first { model.pick = .model(.claude, top.name) }
            }
            try shot("week") { $0.period = .week }
            try shot("month") { $0.period = .month }
            try shot("moved-aside") { model in
                let moved = roots.data.appendingPathComponent("token-ledger.unreadable-20261103T014600Z.json").path
                model.preview(result: TokenScanResult(ledger: result.ledger, movedAside: moved, files: result.files), now: now)
            }
            try shot("empty") { $0.preview(result: TokenScanResult(ledger: TokenLedger(), files: 0), now: now) }
            try shot("loading") { $0.previewProgress(nil) }

            let full = TokensModel(env: env)
            full.preview(result: result, now: now)
            if let board = full.board {
                for bucket in board.buckets.prefix(3) where !bucket.both.isEmpty { full.expanded.insert(bucket.id) }
            }
            try write(FullBoard(model: full).reinsRoot(shell: shell(for: full, choice: choice), toasts: env.toasts, env: env),
                      name: "tokens-board-full", choice: choice, to: directory, fullHeight: true, echo: choice == .dark)
        }
    }

    /// Runs the scan and spins the main run loop until it lands; the scanner is an actor, so this does not deadlock.
    private static func scanBeforeRendering(_ model: TokensModel) throws -> TokenScanResult {
        Task { await model.scan() }
        let deadline = Date().addingTimeInterval(120)
        while model.result == nil, model.failure == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard let result = model.result else {
            throw ShotFailure(errorDescription: model.failure ?? "the token scan did not finish in 120 s")
        }
        return result
    }

    private static func shell(for model: TokensModel, choice: AppearanceChoice) -> ShellModel {
        let tabs: [any ReinsTab] = TabRegistry.makeTabs().map { $0.id == TokensTab.tabID ? TokensTab(model: model) : $0 }
        return ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), activeID: TokensTab.tabID)
    }

    private static func screen(_ model: TokensModel, env: AppEnvironment, choice: AppearanceChoice) -> some View {
        ShellView()
            .reinsRoot(shell: shell(for: model, choice: choice), toasts: env.toasts, env: env)
            .frame(width: ShotRenderer.size.width, height: ShotRenderer.size.height)
    }

    private static func write<V: View>(_ view: V, name: String, choice: AppearanceChoice, to directory: URL, fullHeight: Bool = false, echo: Bool) throws {
        try ShotRenderer.write(view, name: name, choice: choice, to: directory, fullHeight: fullHeight)
        guard echo, ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else { return }
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, choice.colorScheme).environment(\.isShotRendering, true))
        renderer.scale = 1
        if fullHeight { renderer.proposedSize = ProposedViewSize(width: ShotRenderer.size.width, height: nil) }
        guard let image = renderer.cgImage,
              let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else { return }
        print("REINS-SHOT-BEGIN \(name)-\(choice.rawValue).jpg")
        print(jpeg.base64EncodedString(options: [.lineLength76Characters]))
        print("REINS-SHOT-END")
    }
}

/// The whole board at its full height, below the fold included, for one screenshot.
private struct FullBoard: View {
    let model: TokensModel
    @FocusState private var focus: TokensFocus?

    var body: some View {
        if let board = model.board {
            VStack(alignment: .leading, spacing: 8) {
                TokensToolsRow(model: model, board: board)
                TokensBoardView(model: model, board: board, focus: $focus)
            }
            .padding(Metrics.pagePadding)
            .frame(width: ShotRenderer.size.width - Metrics.sidebarWidth, alignment: .topLeading)
            .background(Palette.background)
        }
    }
}
