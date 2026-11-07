import CoreText
import Testing
@testable import Reins

@Suite("Inter, the only typeface")
struct InterFontTests {
    @Test("the bundled font registers and each weight resolves to its named instance")
    func registersEveryWeight() {
        #expect(InterFont.isRegistered)
        for (weight, name) in [(InterFont.Weight.regular, "InterVariable"), (.medium, "InterVariable-Medium"), (.semibold, "InterVariable-SemiBold")] {
            #expect(CTFontCopyPostScriptName(InterFont.font(weight, size: 14)) as String == name)
        }
    }

    @Test("text roles use only 12, 14 and 16, plus the figure and display exceptions, on a 4 pt line box")
    func rolesStayOnTheScale() {
        let text: [ReinsType] = [.caption, .captionStrong, .label, .body, .bodyStrong, .rowTitle, .title, .paletteInput, .code, .codeTitle, .number, .numberStrong, .count, .countStrong]
        for role in text {
            #expect([12, 14, 16].contains(role.size))
            #expect(role.lineBox.truncatingRemainder(dividingBy: 4) == 0)
            #expect(role.lineBox >= role.naturalLineHeight)
        }
        #expect(ReinsType.figure.size == 24 && ReinsType.figure.lineBox == 32)
        let display = ReinsType.display
        #expect(display.size == 72 && display.lineBox == 88 && display.lineBox >= display.naturalLineHeight)
        #expect(display.lineBox.truncatingRemainder(dividingBy: 4) == 0)
    }

    @Test("numbers in columns are tabular, prose is not (Inter's tnum widens the hyphen), machine strings disambiguate")
    func features() {
        func tags(_ role: ReinsType) -> Set<String> {
            let settings = CTFontCopyFeatureSettings(role.ctFont) as? [[String: Any]] ?? []
            return Set(settings.compactMap { $0[kCTFontOpenTypeFeatureTag as String] as? String })
        }
        #expect(tags(.body).isEmpty)
        #expect(tags(.caption).isEmpty)
        #expect(tags(.number) == ["tnum"])
        #expect(tags(.count) == ["tnum"])
        #expect(tags(.code) == ["ss02", "zero"])
        #expect(tags(.codeTitle) == ["ss02", "zero"])
    }

    /// The v5 type table (spec, "Type"): size, weight, line box and the mock body's features on every new role.
    @Test("v5 roles: 10 to 28 with the mock's weights, line boxes and features")
    func v5Roles() {
        let expected: [(ReinsType, CGFloat, InterFont.Weight, CGFloat)] = [
            (.micro, 10, .medium, 12), (.small, 11, .regular, 16), (.smallLabel, 11, .medium, 16), (.meta, 12, .regular, 16),
            (.metaLabel, 12, .medium, 16), (.prose, 13, .regular, 20), (.rowName, 13, .book, 20), (.control, 13, .medium, 20),
            (.controlStrong, 13, .semibold, 20), (.field, 14, .regular, 20), (.cardTitle, 16, .semibold, 24),
            (.heading, 20, .semibold, 28), (.answer, 28, .semibold, 32),
        ]
        for (role, size, weight, lineBox) in expected {
            #expect(role.size == size && role.weight == weight && role.lineBox == lineBox, "\(size) pt role")
            #expect(role.lineBox.truncatingRemainder(dividingBy: 4) == 0)
            let settings = CTFontCopyFeatureSettings(role.ctFont) as? [[String: Any]] ?? []
            #expect(Set(settings.compactMap { $0[kCTFontOpenTypeFeatureTag as String] as? String }) == ["tnum", "cv11", "ss03"])
        }
        #expect(ReinsType.cardTitle.trackingEm == -0.01 && ReinsType.heading.trackingEm == -0.01 && ReinsType.answer.trackingEm == -0.02)
    }

    @Test("the 450 row-name weight is the variable font moved on its weight axis")
    func bookWeight() {
        let variation = CTFontCopyVariation(InterFont.font(.book, size: 13)) as? [Int: Double] ?? [:]
        #expect(variation[InterFont.weightAxis] == 450)
    }
}
