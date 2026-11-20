import Testing
@testable import SpaceVibe

/// V5-A16 and V5-R46: green, amber and red mean state only. Measured as OKLCH hue in both appearances: a state family is
/// its hue ±20° (the working threshold, which the owner's eye at the final eye task may move); every category, the Claude
/// identity colour and the accent sit outside every state family, and no two of them share a hue (also within 20°).
/// Activity's session states (the glance widget, GW-R2) are states too, and stay apart from each other. Codex's identity
/// is the text colour, so it and the other neutrals carry no hue to collide.
@Suite("Hue policy: one colour, one meaning (V5-A16)", .fixtureCLIs)
struct HuePolicyTests {
    static let familyHalfWidth = 20.0
    /// Below this OKLCH chroma a colour reads as grey and its hue angle means nothing.
    static let achromaticChroma = 0.02

    private typealias P = PaletteValue

    /// Activity's session states: working, waiting and done. Unmeasurable and idle use `mute`, which has no hue.
    static let sessionStates: [(String, ColorValue)] = [
        ("sessionWorking", P.sessionWorking), ("sessionWaiting", P.sessionWaiting), ("sessionDone", P.sessionDone),
    ]
    static let states: [(String, ColorValue)] = [("ok", P.ok), ("warn", P.warn), ("bad", P.bad)] + sessionStates
    /// Hues that must stay apart from the states and from each other.
    static let meanings: [(String, ColorValue)] = [
        ("catSkill", P.catSkill), ("catSubagent", P.catSubagent), ("catHook", P.catHook), ("catRule", P.catRule),
        ("claude", P.claude), ("accent", P.accent),
    ]

    private static func lch(_ value: ColorValue, _ appearance: Appearance) -> (l: Double, c: Double, h: Double) {
        ColorMath.oklch(value.rgb(appearance))
    }

    @Test("categories, Claude and the accent sit outside every state family")
    func outsideStateFamilies() {
        for appearance in Appearance.allCases {
            for (name, value) in Self.meanings {
                let hue = Self.lch(value, appearance).h
                for (state, stateValue) in Self.states {
                    let distance = ColorMath.hueDistance(hue, Self.lch(stateValue, appearance).h)
                    #expect(distance > Self.familyHalfWidth,
                            "\(appearance): \(name) (hue \(String(format: "%.1f", hue))) is \(String(format: "%.1f", distance))° from \(state)")
                }
            }
        }
    }

    @Test("no two categories, nor a category and Claude or the accent, share a hue")
    func apartFromEachOther() {
        for appearance in Appearance.allCases {
            for (i, (a, aValue)) in Self.meanings.enumerated() {
                for (b, bValue) in Self.meanings.dropFirst(i + 1) {
                    let distance = ColorMath.hueDistance(Self.lch(aValue, appearance).h, Self.lch(bValue, appearance).h)
                    #expect(distance > Self.familyHalfWidth, "\(appearance): \(a) and \(b) are \(String(format: "%.1f", distance))° apart")
                }
            }
        }
    }

    @Test("working, waiting and done do not share a hue")
    func sessionStatesApart() {
        for appearance in Appearance.allCases {
            for (i, (a, aValue)) in Self.sessionStates.enumerated() {
                for (b, bValue) in Self.sessionStates.dropFirst(i + 1) {
                    let distance = ColorMath.hueDistance(Self.lch(aValue, appearance).h, Self.lch(bValue, appearance).h)
                    #expect(distance > Self.familyHalfWidth, "\(appearance): \(a) and \(b) are \(String(format: "%.1f", distance))° apart")
                }
            }
        }
    }

    @Test("every hue this policy measures is chromatic, and Codex and the neutrals are not")
    func chroma() {
        for appearance in Appearance.allCases {
            for (name, value) in Self.states + Self.meanings {
                #expect(Self.lch(value, appearance).c >= Self.achromaticChroma, "\(appearance): \(name) has no measurable hue")
            }
            for (name, value) in [("codex", P.codex), ("mute", P.mute), ("fg", P.fg), ("fg2", P.fg2), ("fg3", P.fg3), ("fg4", P.fg4)] {
                #expect(Self.lch(value, appearance).c < Self.achromaticChroma, "\(appearance): \(name) has a hue it must not carry")
            }
        }
    }
}
