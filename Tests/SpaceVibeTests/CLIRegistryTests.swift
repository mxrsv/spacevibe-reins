import Foundation
import Testing
@testable import SpaceVibe

/// `CLIRegistry` is the one table of each CLI's look (MC-R1, MC27): every CLI the core lists has a complete look, and no CLI's
/// colour reads as a state or as the accent (PRODUCT.md colour meanings, MC-R12). Every other fact comes from `clis.list`
/// (`CLICatalogTests`).
@Suite("CLI registry: one complete look per CLI", .fixtureCLIs)
struct CLIRegistryTests {
    private typealias P = PaletteValue

    /// Every look in the table, and the neutral one a CLI without an entry takes.
    static var looks: [(id: String, look: CLILook)] {
        CLIRegistry.looks.map { ($0.key.rawValue, $0.value) }.sorted { $0.id < $1.id } + [("neutral", CLIRegistry.neutral)]
    }

    static var brandFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SpaceVibeTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // checkout
            .appendingPathComponent("Resources/Brand")
    }

    @Test("every CLI the core lists has its own look in the table")
    func everyListedCLIHasALook() {
        for info in CLICatalogFixture.list {
            #expect(CLIRegistry.looks[info.id] != nil, "\(info.id) has no look: add its mark and tone to CLIRegistry")
        }
    }

    @Test("every look has a mark that exists and a full tone; the neutral look has no mark")
    func looksAreComplete() {
        #expect(!CLIRegistry.looks.isEmpty)
        for (id, look) in CLIRegistry.looks.map({ ($0.key.rawValue, $0.value) }) {
            let mark = look.mark
            #expect(mark != nil, "\(id) has no mark")
            if let mark {
                #expect(mark.fileName.hasSuffix(".svg"), "\(id): \(mark.fileName)")
                let url = Self.brandFolder.appendingPathComponent(mark.fileName)
                #expect(FileManager.default.fileExists(atPath: url.path), "\(id): no mark at \(url.path)")
            }
        }
        for (id, look) in Self.looks {
            let fill = look.tone.fillValue
            #expect(fill.lightAlpha == 1 && fill.darkAlpha == 1, "\(id): the fill must be opaque")
            if let opacity = look.tone.barOpacity { #expect(opacity > 0 && opacity < 1, "\(id): bar opacity \(opacity)") }
        }
        let marks = CLIRegistry.looks.values.compactMap { $0.mark?.fileName }
        #expect(Set(marks).count == marks.count, "two looks share a mark")
        #expect(CLIRegistry.neutral.mark == nil, "the neutral look draws the tone's dot, never another CLI's mark")
    }

    /// The colours that mean a state, and the accent's: a CLI tone is none of them.
    static let reserved: [(String, ColorValue)] = [
        ("ok", P.ok), ("warn", P.warn), ("bad", P.bad), ("badSolid", P.badSolid), ("badText", P.badText),
        ("successInk", P.successInk), ("warnInk", P.warnInk), ("dangerInk", P.dangerInk),
        ("accent", P.accent), ("accentText", P.accentText), ("accentSolid", P.accentSolid), ("accentBg", P.accentBg),
        ("accentInk", P.accentInk),
    ] + HuePolicyTests.sessionStates

    private static func same(_ a: ColorValue, _ b: ColorValue) -> Bool {
        a.light == b.light && a.dark == b.dark && a.lightAlpha == b.lightAlpha && a.darkAlpha == b.darkAlpha
    }

    /// A grey tone (Codex's text colour, Gemini CLI's neutral) has no hue to collide; a chromatic one keeps out of every state's
    /// hue family and the accent's, as `HuePolicyTests` measures them.
    @Test("no CLI tone is a state colour or the accent, nor sits in their hue family")
    func tonesKeepClearOfStatesAndAccent() {
        let hueFamilies = HuePolicyTests.states + [("accent", P.accent)]
        for (id, look) in Self.looks {
            let tone = look.tone.fillValue
            for (name, value) in Self.reserved {
                #expect(!Self.same(tone, value), "\(id)'s tone is the \(name) token")
            }
            for appearance in Appearance.allCases {
                let lch = ColorMath.oklch(tone.rgb(appearance))
                guard lch.c >= HuePolicyTests.achromaticChroma else { continue }
                for (name, value) in hueFamilies {
                    let distance = ColorMath.hueDistance(lch.h, ColorMath.oklch(value.rgb(appearance)).h)
                    #expect(distance > HuePolicyTests.familyHalfWidth,
                            "\(appearance): \(id)'s tone is \(String(format: "%.1f", distance))° from \(name)")
                }
            }
        }
    }
}
