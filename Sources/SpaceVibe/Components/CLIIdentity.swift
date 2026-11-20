import SwiftUI

/// Everything the UI knows about one CLI: the facts the core sent in `clis.list` and the look `CLIRegistry` holds for its id.
/// Each value is one entry of `CLICatalog`; a screen reads these fields and never branches on which CLI it holds (MC-R1).
struct CLIIdentity: Sendable {
    /// The id the core writes on the wire.
    let id: CLIID
    /// The CLI's name as the core's registry writes it (GLOSSARY).
    let label: String
    let look: CLILook
    /// Its folder or binary exists (MC8). A CLI that is not installed still shows where the page says so ("not installed").
    let installed: Bool
    let concepts: Set<CoreCLIConcept>
    /// Skill, agent and hook, in that order.
    let kinds: [CoreKindInfo]
    /// Where its Limits reading comes from, which decides what the Limits page says before and about a reading; nil without the
    /// limits concept.
    let limitsReading: CLILimitsReading?
    /// Whether SpaceVibe reads its sessions from a log. Without one, Activity shows a band that says so.
    let readsSessionLog: Bool
    /// Whether it logs hook runs, so a hook only it has can be counted.
    let logsHookRuns: Bool
    /// The code of the Activity limit (`CoreActivityLimit.code`) that says why a waiting session of this CLI cannot be told
    /// apart from a busy one; nil when it has none. A session row shows that limit's text.
    let approvalLimitCode: String?
    /// Whether a subagent with no `tools` line inherits every tool (Claude Code's subagent docs), so a copy made into it, which
    /// carries no `tools` line, can use every tool.
    let subagentWithoutToolsGetsEveryTool: Bool

    init(_ info: CoreCLIInfo, look: CLILook) {
        id = info.id
        label = info.label
        self.look = look
        installed = info.installed
        concepts = Set(info.concepts)
        kinds = info.kinds
        limitsReading = info.limitsReading
        readsSessionLog = info.readsSessionLog
        logsHookRuns = info.logsHookRuns
        approvalLimitCode = info.approvalLimitCode
        subagentWithoutToolsGetsEveryTool = info.subagentWithoutToolsGetsEveryTool
    }

    var mark: CLIMarkArt? { look.mark }
    var tone: CLITone { look.tone }

    func has(_ concept: CoreCLIConcept) -> Bool { concepts.contains(concept) }

    /// What the CLI does with `kind`; nil when the core did not describe it, which reads as absent.
    func kind(_ kind: CoreKind) -> CoreKindInfo? { kinds.first { $0.kind == kind } }

    /// The CLI has `kind` at all (its support is not `absent`).
    func hasKind(_ kind: CoreKind) -> Bool { (self.kind(kind)?.support ?? .absent) != .absent }

    /// What a screen asks about an id the catalog does not hold (unknown to the core, or turned off). The filter in `CLICatalog`
    /// keeps such an id off every page, so this is only ever read by a bug: the id as its name, the neutral look, no facts.
    static func unlisted(_ id: CLIID) -> CLIIdentity {
        CLIIdentity(CoreCLIInfo(id: id, label: id.rawValue, installed: false, concepts: [], kinds: [], limitsReading: nil,
                                logsHookRuns: false, readsSessionLog: false, approvalLimitCode: nil,
                                subagentWithoutToolsGetsEveryTool: false),
                    look: CLIRegistry.neutral)
    }
}

/// A CLI's look: its mark and its identity tone (`CLIRegistry`).
struct CLILook: Sendable {
    /// Nil for a CLI with no mark in the table: `CLIMark` draws the tone's dot.
    let mark: CLIMarkArt?
    let tone: CLITone
}

/// A CLI's brand mark: an SVG in `Resources/Brand`. A monochrome mark is drawn as a template in `brandMonochrome`; any other
/// keeps the artwork's own colours.
struct CLIMarkArt: Sendable {
    let fileName: String
    let isMonochrome: Bool
}

/// The colour a CLI carries (identity only, never a state or the accent; `CLIRegistryTests`). Built from a `PaletteValue`
/// token, so a test reads the token's values and a view reads the colour made from it once.
struct CLITone: Sendable {
    /// The identity colour's values.
    let fillValue: ColorValue
    /// How much of the fill a usage bar takes; nil draws the fill as it is.
    let barOpacity: Double?

    /// The identity colour: a mark's stand-in dot.
    let fill: Color
    /// A usage bar's fill (the Skills pane's meters).
    let bar: Color

    init(fill: ColorValue, barOpacity: Double? = nil) {
        fillValue = fill
        self.barOpacity = barOpacity
        let fillColor = fill.color
        self.fill = fillColor
        bar = barOpacity.map { fillColor.opacity($0) } ?? fillColor
    }
}
