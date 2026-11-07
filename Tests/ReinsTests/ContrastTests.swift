import Testing
@testable import Reins

/// V5-A2 and V5-R40: every text and meaning-carrying pair on its real, composited ground, in both appearances: text
/// 4.5:1, marks (state glyphs and dots, CLI bars, the verdict cut-out) 3:1. A miss is fixed in `PaletteValue`, never
/// exempted here. The grounds are where the tokens are drawn, in the frozen mock and in the screens not yet rebuilt.
@Suite("Contrast: every text and mark on its real ground (V5-A2)")
struct ContrastTests {
    struct Ground: Sendable {
        let name: String
        let layers: [Layer]
        var brighten: Double = 0
    }

    struct Pair: Sendable, CustomTestStringConvertible {
        let ink: String
        let value: ColorValue
        let ground: Ground
        let minimum: Double
        var testDescription: String { "\(ink) on \(ground.name)" }
    }

    private typealias P = PaletteValue

    private static func ground(_ name: String, _ base: ColorValue, _ tops: Layer...) -> Ground {
        Ground(name: name, layers: [Layer(base)] + tops)
    }

    /// Where text sits: every surface, and the current, hovered and picked fills over the ones rows and items sit on.
    /// `sel` is also the focus fill (D57), so "on a focused control" is covered by the `sel` rows.
    static let textGrounds: [Ground] = [
        ground("bgSide", P.bgSide), ground("bgApp", P.bgApp), ground("bgPanel", P.bgPanel), ground("bgRaise", P.bgRaise),
        ground("bgSunk", P.bgSunk), ground("bgPop", P.bgPop), ground("bgBand", P.bgBand),
        ground("bgBandHover", P.bgBandHover), ground("bgBandFocus", P.bgBandFocus),
        ground("sel on bgPanel", P.bgPanel, Layer(P.sel)), ground("sel on bgRaise", P.bgRaise, Layer(P.sel)),
        ground("sel on bgPop", P.bgPop, Layer(P.sel)), ground("sel on bgSide", P.bgSide, Layer(P.sel)),
        ground("hover on bgPanel", P.bgPanel, Layer(P.hover)), ground("hover on bgRaise", P.bgRaise, Layer(P.hover)),
        ground("hover on bgPop", P.bgPop, Layer(P.hover)), ground("accentBg on bgPanel", P.bgPanel, Layer(P.accentBg)),
    ]

    /// Where a state glyph, dot or badge sits: rows (rest, current, hovered, picked), cards, popovers and band headers.
    static let markGrounds: [Ground] = [
        ground("bgPanel", P.bgPanel), ground("bgRaise", P.bgRaise), ground("bgPop", P.bgPop), ground("bgBand", P.bgBand),
        ground("sel on bgPanel", P.bgPanel, Layer(P.sel)), ground("sel on bgRaise", P.bgRaise, Layer(P.sel)),
        ground("hover on bgRaise", P.bgRaise, Layer(P.hover)), ground("accentBg on bgPanel", P.bgPanel, Layer(P.accentBg)),
    ]

    private static func text(_ ink: String, _ value: ColorValue, on grounds: [Ground]) -> [Pair] {
        grounds.map { Pair(ink: ink, value: value, ground: $0, minimum: 4.5) }
    }

    private static func marks(_ ink: String, _ value: ColorValue, on grounds: [Ground]) -> [Pair] {
        grounds.map { Pair(ink: ink, value: value, ground: $0, minimum: 3) }
    }

    /// A tab's colour: its fill, the active text and the active count (spec, "Category colours").
    private static let tabColors: [(String, ColorValue, ColorValue, ColorValue)] = [
        ("catSkill", P.catSkill, P.catSkillInk, P.catSkillCountInk),
        ("catSubagent", P.catSubagent, P.catSubagentInk, P.catSubagentCountInk),
        ("catHook", P.catHook, P.catHookInk, P.catHookCountInk),
        ("catRule", P.catRule, P.catRuleInk, P.catRuleCountInk),
        ("accent", P.accent, P.accentInk, P.accentCountInk),
    ]

    private static var tabChipPairs: [Pair] {
        let inactive = Layer(P.fg, alpha: TabChipAlpha.rest)
        let hovered = Layer(P.fg, alpha: TabChipAlpha.hover)
        let circle = Layer(P.fg, alpha: TabChipAlpha.count)
        var pairs = [
            Pair(ink: "fg2", value: P.fg2, ground: ground("an inactive tab chip", P.bgPanel, inactive), minimum: 4.5),
            Pair(ink: "fg2", value: P.fg2, ground: ground("an inactive tab's count circle", P.bgPanel, inactive, circle), minimum: 4.5),
            Pair(ink: "fg", value: P.fg, ground: ground("a hovered tab chip", P.bgPanel, hovered), minimum: 4.5),
            Pair(ink: "fg", value: P.fg, ground: ground("a hovered tab's count circle", P.bgPanel, hovered, circle), minimum: 4.5),
        ]
        for (name, fill, ink, countInk) in tabColors {
            let active = Layer(fill, alpha: TabChipAlpha.active)
            let focused = Layer(fill, alpha: TabChipAlpha.activeFocus)
            let count = Layer(fill, alpha: TabChipAlpha.activeCount)
            pairs += [
                Pair(ink: "\(name)Ink", value: ink, ground: ground("the active \(name) chip", P.bgPanel, active), minimum: 4.5),
                Pair(ink: "\(name)Ink", value: ink, ground: ground("the focused active \(name) chip", P.bgPanel, focused), minimum: 4.5),
                Pair(ink: "\(name)CountInk", value: countInk, ground: ground("the active \(name) count circle", P.bgPanel, active, count),
                     minimum: 4.5),
                Pair(ink: "\(name)CountInk", value: countInk,
                     ground: ground("the focused active \(name) count circle", P.bgPanel, focused, count), minimum: 4.5),
            ]
        }
        return pairs
    }

    /// The screens not yet rebuilt: text in a state or CLI colour (tags, banners, state tiles, the Limits figure) on
    /// surfaces and on its own tint; the primary text on every tint (a banner's message, a Limits sidebar tile's name and
    /// share), the secondary text on the state tints (a banner's detail).
    private static var oldScreenPairs: [Pair] {
        let inks: [(String, ColorValue, ColorValue, Bool)] = [
            ("successInk", P.successInk, P.ok, true), ("warnInk", P.warnInk, P.warn, true), ("dangerInk", P.dangerInk, P.bad, true),
            ("claudeInk", P.claudeInk, P.claude, false), ("codexInk", P.codexInk, P.codex, false),
        ]
        var pairs: [Pair] = []
        for (name, ink, fill, isState) in inks {
            let tint = Layer(P.tint(of: fill))
            let tints = [("bgPanel", P.bgPanel), ("bgSide", P.bgSide), ("bgRaise", P.bgRaise)].map { base in
                ground("the \(name) tint on \(base.0)", base.1, tint)
            }
            pairs += text(name, ink, on: [
                ground("bgPanel", P.bgPanel), ground("bgRaise", P.bgRaise), ground("bgSide", P.bgSide),
                ground("sel on bgPanel", P.bgPanel, Layer(P.sel)), ground("hover on bgRaise", P.bgRaise, Layer(P.hover)),
            ] + tints)
            pairs += text("fg", P.fg, on: tints) + (isState ? text("fg2", P.fg2, on: tints) : [])
        }
        // The toast is an inverted surface: `background` (`bgApp`) text on `text` (`fg`).
        pairs.append(Pair(ink: "bgApp", value: P.bgApp, ground: ground("the toast (fg)", P.fg), minimum: 4.5))
        return pairs
    }

    static var pairs: [Pair] {
        var all = text("fg", P.fg, on: textGrounds) + text("fg2", P.fg2, on: textGrounds) + text("fg3", P.fg3, on: textGrounds)
        // The accent as text: links, `Clear`, the toast's `Undo` at rest, hovered and focused.
        all += text("accentText", P.accentText, on: [
            ground("bgPanel", P.bgPanel), ground("bgRaise", P.bgRaise), ground("bgPop", P.bgPop),
            ground("hover on bgPop", P.bgPop, Layer(P.hover)), ground("sel on bgPop", P.bgPop, Layer(P.sel)),
        ])
        // White on the solid fills: the primary button (at rest and with its hover brightening), the switch, Stop.
        all += [
            Pair(ink: "onAccent", value: P.onAccent, ground: ground("accentSolid", P.accentSolid), minimum: 4.5),
            Pair(ink: "onAccent", value: P.onAccent,
                 ground: Ground(name: "accentSolid brightened for hover", layers: [Layer(P.accentSolid)], brighten: 0.08), minimum: 4.5),
            Pair(ink: "onAccent", value: P.onAccent, ground: ground("badSolid", P.badSolid), minimum: 4.5),
        ]
        all += tabChipPairs
        // The accent as a mark: the current row's bar, a picked checkbox.
        for (name, value) in [("ok", P.ok), ("warn", P.warn), ("bad", P.bad), ("mute", P.mute), ("accent", P.accent)] {
            all += marks(name, value, on: markGrounds)
        }
        // CLI status dots in the sidebar.
        all += marks("ok", P.ok, on: [ground("bgSide", P.bgSide)]) + marks("mute", P.mute, on: [ground("bgSide", P.bgSide)])
        // Identity marks: a meter bar on its track, a tag's dot on `bgRaise`.
        for (name, value) in [("claude", P.claude), ("codex", P.codex)] {
            all += marks(name, value, on: [
                ground("bgRaise", P.bgRaise), ground("track on bgRaise", P.bgRaise, Layer(P.track)),
                ground("track on bgPanel", P.bgPanel, Layer(P.track)),
            ])
        }
        // What sits on a hovered or focused band header beside its text (V5-R55): the state glyph (warn, danger) and a CLI
        // logo. The band at rest is in `markGrounds`.
        for (name, value) in [("warn", P.warn), ("bad", P.bad), ("claude", P.claude), ("codex", P.codex)] {
            all += marks(name, value, on: [ground("bgBandHover", P.bgBandHover), ground("bgBandFocus", P.bgBandFocus)])
        }
        // A bar cell's fill on its track (V5-R56): neutral, warn and danger, in a card row at rest, hovered and current.
        for (name, value) in [("fg2", P.fg2), ("warn", P.warn), ("bad", P.bad)] {
            all += marks("\(name) bar", value, on: [
                ground("track on bgRaise", P.bgRaise, Layer(P.track)),
                ground("track on hover on bgRaise", P.bgRaise, Layer(P.hover), Layer(P.track)),
                ground("track on sel on bgRaise", P.bgRaise, Layer(P.sel), Layer(P.track)),
            ])
        }
        // The cut-out inside a verdict glyph (`fg2`).
        all.append(Pair(ink: "onVerdict", value: P.onVerdict, ground: ground("a verdict glyph (fg2)", P.fg2), minimum: 3))
        return all + oldScreenPairs
    }

    @Test("each pair reads at its minimum in both appearances", arguments: pairs)
    func pairReads(_ pair: Pair) {
        for appearance in Appearance.allCases {
            let ground = ColorMath.composite(pair.ground.layers, appearance, brighten: pair.ground.brighten)
            // An opaque ink is itself; a translucent one is seen over its ground.
            let ink = ColorMath.composite(pair.ground.layers + [Layer(pair.value)], appearance)
            let ratio = ColorMath.contrast(ink, ground)
            #expect(ratio >= pair.minimum,
                    "\(appearance): \(pair.ink) \(ink.hex) on \(pair.ground.name) \(ground.hex) is \(String(format: "%.2f", ratio)):1, needs \(pair.minimum):1")
        }
    }

    /// D57 and V5-R41: focus is the `sel` fill. Every text and mark on it is in `pairs` (each `sel` ground is also the
    /// focused case); here the fill must change the look from rest and stand a step above hover, in both appearances. Its
    /// contrast with the unfocused state (WCAG 2.4.13, AAA) is about 1.1:1, not 3:1: an open trade-off for the owner at the
    /// final eye task.
    @Test("the focus fill differs from rest and from hover")
    func focusFillDiffers() {
        let bases: [(String, ColorValue)] = [("bgSide", P.bgSide), ("bgPanel", P.bgPanel), ("bgRaise", P.bgRaise), ("bgPop", P.bgPop)]
        for appearance in Appearance.allCases {
            for (name, base) in bases {
                let rest = ColorMath.composite([Layer(base)], appearance)
                let hovered = ColorMath.composite([Layer(base), Layer(P.hover)], appearance)
                let focused = ColorMath.composite([Layer(base), Layer(P.sel)], appearance)
                let fromRest = ColorMath.contrast(focused, rest)
                let fromHover = ColorMath.contrast(focused, hovered)
                #expect(fromRest > ColorMath.contrast(hovered, rest) && fromHover >= 1.02,
                        "\(appearance) on \(name): focus \(focused.hex) is \(String(format: "%.3f", fromRest)):1 from rest, \(String(format: "%.3f", fromHover)):1 from hover")
            }
        }
    }

    @Test("the pair list covers what V5-A2 names")
    func coversTheNamedPairs() {
        let names = Set(Self.pairs.map(\.testDescription))
        for required in [
            "fg3 on bgRaise", "fg3 on sel on bgRaise", "fg on bgRaise", "fg2 on an inactive tab chip",
            "fg2 on an inactive tab's count circle", "catSkillInk on the active catSkill chip",
            "catSkillCountInk on the active catSkill count circle", "accentInk on the active accent chip",
            "warn on bgPanel", "warn on bgRaise", "bad on bgPanel", "bad on bgRaise", "onVerdict on a verdict glyph (fg2)",
            "fg2 on sel on bgRaise", "fg3 on sel on bgPanel",
            "fg3 on bgBandHover", "fg3 on bgBandFocus", "warn on bgBandHover", "warn on bgBandFocus",
            "warn bar on track on sel on bgRaise",
        ] {
            #expect(names.contains(required), "missing \(required)")
        }
    }
}
