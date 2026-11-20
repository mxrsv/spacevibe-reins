import Foundation

/// The one table of each CLI's look (MC-R1, MC27): its mark and its identity tone, keyed by the core's id. Every other fact
/// about a CLI (its label, the concepts and item kinds it has, where its limits come from, how its hooks are logged) comes from
/// the core's `clis.list`, joined to this table in `CLICatalog`. Every other file asks the catalog through `cli.identity` (or
/// its lists) and never names a CLI itself; `CLIBranchPolicyTests` fails on a CLI literal outside this file and `Core/`.
///
/// Adding a CLI's look: add its id constant below, its entry in `looks`, its mark to `Resources/Brand` and its tone to
/// `PaletteValue` (`CLIRegistryTests` checks the mark exists and the tone keeps clear of the states and the accent). A CLI the
/// core lists with no entry here still shows, with the `neutral` look; nothing falls back to another CLI's look.
enum CLIRegistry {
    static let looks: [CLIID: CLILook] = [
        .claude: CLILook(mark: CLIMarkArt(fileName: "claude-spark-clay.svg", isMonochrome: false), tone: CLITone(fill: PaletteValue.claude)),
        // Codex's colour is the text colour; its bar is a little quieter than Claude's clay.
        .codex: CLILook(mark: CLIMarkArt(fileName: "codex-blossom-white.svg", isMonochrome: true),
                        tone: CLITone(fill: PaletteValue.codex, barOpacity: Metrics.Bar.codexOpacity)),
        // Gemini CLI has no brand colour in the app, so it reads neutral.
        .gemini: CLILook(mark: CLIMarkArt(fileName: "gemini.svg", isMonochrome: false), tone: CLITone(fill: PaletteValue.fg2)),
    ]

    /// The look of a CLI the core lists and this table does not: no mark (`CLIMark` draws the tone's dot) and the neutral tone.
    static let neutral = CLILook(mark: nil, tone: CLITone(fill: PaletteValue.fg2))

    static func look(_ id: CLIID) -> CLILook { looks[id] ?? neutral }
}

/// The ids the look table, the tests and the synthetic shots name. Screens never do (`CLIBranchPolicyTests`).
extension CLIID {
    static let claude = CLIID("claude")
    static let codex = CLIID("codex")
    static let gemini = CLIID("gemini")
}
