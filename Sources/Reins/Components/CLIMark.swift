import AppKit
import ReinsCore
import SwiftUI

/// The colour a CLI carries on the Limits surface. Gemini CLI has no brand colour in the app, so it reads neutral.
extension LimitsCLI {
    var fill: Color {
        switch self {
        case .claude: Palette.claude
        case .codex: Palette.codex
        case .gemini: Palette.textSecondary
        }
    }

    var ink: Color {
        switch self {
        case .claude: Palette.claudeInk
        case .codex: Palette.codexInk
        case .gemini: Palette.textSecondary
        }
    }

    var tint: Color {
        switch self {
        case .claude: Palette.claudeTint
        case .codex: Palette.codexTint
        case .gemini: Palette.surfaceRaised
        }
    }
}

/// A CLI's brand mark in a tinted rounded square: 40 pt beside a card title, 24 pt (`small`) in a sidebar tile. Claude Code
/// and Codex are drawn as a template in the CLI's ink on its tint; Gemini CLI keeps its own colours. Decorative: the name
/// is always written beside it.
struct CLIMark: View {
    let cli: LimitsCLI
    var small = false

    init(_ cli: LimitsCLI, small: Bool = false) {
        self.cli = cli
        self.small = small
    }

    var body: some View {
        let side = small ? Metrics.cliMarkSmallSize : Metrics.cliMarkSize
        let shape = RoundedRectangle(cornerRadius: small ? Metrics.controlRadius : Metrics.groupRadius, style: .continuous)
        ZStack {
            shape.fill(cli.tint)
            if let image = BrandMark.image(cli) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(cli == .gemini ? .original : .template)
                    .scaledToFit()
                    .foregroundStyle(cli.ink)
                    .frame(width: side * Metrics.cliMarkGlyphFraction, height: side * Metrics.cliMarkGlyphFraction)
            } else {
                Circle().fill(cli.fill).frame(width: Space.s8, height: Space.s8)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// The brand SVGs in `Resources/Brand`: inside the app bundle, else (debug builds only) in the checkout. A missing file
/// draws a dot instead of failing.
enum BrandMark {
    private static let fileNames: [LimitsCLI: String] = [
        .claude: "claude-spark-clay.svg",
        .codex: "codex-blossom-white.svg",
        .gemini: "gemini.svg",
    ]

    @MainActor private static var cache: [LimitsCLI: NSImage] = [:]

    @MainActor
    static func image(_ cli: LimitsCLI) -> NSImage? {
        if let cached = cache[cli] { return cached }
        guard let name = fileNames[cli],
              let url = [Bundle.main.resourceURL?.appendingPathComponent("Brand/\(name)"), checkoutURL(name)]
                  .compactMap({ $0 })
                  .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[cli] = image
        return image
    }

    // A release binary must not carry the build machine's source path, so only debug builds look in the checkout.
    #if DEBUG
    private static func checkoutURL(_ name: String) -> URL? {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Components
            .deletingLastPathComponent() // Reins
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // checkout
            .appendingPathComponent("Resources/Brand/\(name)")
    }
    #else
    private static func checkoutURL(_ name: String) -> URL? { nil }
    #endif
}
