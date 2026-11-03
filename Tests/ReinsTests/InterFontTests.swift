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

    @Test("text roles use only 12, 14 and 16, plus the figure exception, on a 4 pt line box")
    func rolesStayOnTheScale() {
        let text: [ReinsType] = [.caption, .captionStrong, .label, .body, .bodyStrong, .rowTitle, .title, .paletteInput, .code, .codeTitle, .number, .numberStrong, .count, .countStrong]
        for role in text {
            #expect([12, 14, 16].contains(role.size))
            #expect(role.lineBox.truncatingRemainder(dividingBy: 4) == 0)
            #expect(role.lineBox >= role.naturalLineHeight)
        }
        #expect(ReinsType.figure.size == 24 && ReinsType.figure.lineBox == 32)
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
}
