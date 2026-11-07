import Foundation
import SwiftUI
import Testing
@testable import SpaceVibe

/// Every icon comes from a generated set or from SpaceVibe's own verdict glyphs (V5-A4; the v3 rule DL7 it extends): category
/// glyphs from MingCute Line, sidebar and content glyphs from Phosphor Duotone, Solar only for the screens not yet rebuilt,
/// the CLI marks from `CLIMark`; no SF Symbol outside `Gallery/`, no size under 12, and a credit for every set in use.
/// The checks read `allCases`, so the cut-over that deletes Solar needs no edit here beyond dropping its row.
@Suite("Icon policy: generated sets")
struct IconPolicyTests {
    static var appSources: URL { StyleBoundaryTests.appSources }

    /// One generated set: the type that holds it, the file the generator writes, what its icon names end with, the credit the
    /// About panel must carry and the licence the generator checked.
    struct GlyphSet {
        let glyphs: [any GlyphSource]
        let file: String
        let package: String
        let suffix: String
        let layers: Int
        let credit: String
        let licence: String
    }

    static let sets: [GlyphSet] = [
        GlyphSet(glyphs: SpaceVibeGlyph.allCases, file: "SpaceVibeIconData.swift", package: "@iconify-json/solar", suffix: "-bold-duotone", layers: 2,
                 credit: "Solar by 480 Design", licence: "CC BY 4.0"),
        GlyphSet(glyphs: CategoryGlyph.allCases, file: "CategoryIconData.swift", package: "@iconify-json/mingcute", suffix: "-line", layers: 1,
                 credit: "MingCute by MingCute Design", licence: "Apache-2.0"),
        GlyphSet(glyphs: ContentGlyph.allCases, file: "ContentIconData.swift", package: "@iconify-json/ph", suffix: "-duotone", layers: 2,
                 credit: "Phosphor Icons", licence: "MIT"),
    ]

    /// What only the generated sets may draw. `Image(` is allowed in `brandMarkFile` (the CLI marks are images, not icons).
    static let forbidden: [(name: String, pattern: String)] = [
        ("SF Symbol", #"systemName:|systemImage:|systemSymbolName"#),
        ("image", #"\bImage\("#),
    ]
    static let brandMarkFile = "Components/CLIMark.swift"

    static func source(_ relative: String) throws -> String {
        try String(contentsOf: appSources.appendingPathComponent(relative), encoding: .utf8)
    }

    /// Matches per file under `Sources/SpaceVibe`, `Gallery/` exempt. Whole-line comments are skipped.
    static func violations() throws -> [String: Int] {
        let expressions = forbidden.map { (name: $0.name, regex: try! NSRegularExpression(pattern: $0.pattern)) }
        var result: [String: Int] = [:]
        let root = appSources.path + "/"
        guard let walker = FileManager.default.enumerator(atPath: appSources.path) else { return result }
        for case let relative as String in walker where relative.hasSuffix(".swift") && !relative.hasPrefix("Gallery/") {
            let source = try String(contentsOfFile: root + relative, encoding: .utf8)
            var count = 0
            for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("//") { continue }
                let range = NSRange(line.startIndex..., in: line)
                for expression in expressions where !(expression.name == "image" && relative == brandMarkFile) {
                    count += expression.regex.numberOfMatches(in: line, range: range)
                }
            }
            if count > 0 { result[relative] = count }
        }
        return result
    }

    @Test("no SF Symbol and no other image outside Gallery/")
    func generatedOnly() throws {
        let found = try Self.violations()
        #expect(found.isEmpty, "\(found.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))")
        // The walk itself found the sources: the brand marks file is there and holds its images.
        #expect(FileManager.default.fileExists(atPath: Self.appSources.appendingPathComponent(Self.brandMarkFile).path))
    }

    @Test("the pattern catches what it names")
    func patterns() throws {
        let symbol = try NSRegularExpression(pattern: Self.forbidden[0].pattern)
        let image = try NSRegularExpression(pattern: Self.forbidden[1].pattern)
        func count(_ regex: NSRegularExpression, _ text: String) -> Int { regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) }
        #expect(count(symbol, #"Image(systemName: "trash")"#) == 1)
        #expect(count(symbol, #"Label("Copy", systemImage: "doc.on.doc")"#) == 1)
        #expect(count(image, #"Image(systemName: "trash")"#) == 1)
        #expect(count(image, "SpaceVibeIcon(.trash)") == 0)
        #expect(count(image, "ImageRenderer(content: view)") == 0)
    }

    @Test("every glyph has its layers, inside its 24 pt box, from an icon of its set")
    func glyphs() {
        let box = CGRect(x: 0, y: 0, width: GlyphBox.side, height: GlyphBox.side).insetBy(dx: -0.5, dy: -0.5)
        for set in Self.sets {
            #expect(!set.glyphs.isEmpty, "\(set.file)")
            #expect(Set(set.glyphs.map(\.iconName)).count == set.glyphs.count, "\(set.file) names a glyph twice")
            for glyph in set.glyphs {
                #expect(glyph.iconName.hasSuffix(set.suffix), "\(glyph.iconName) is not a \(set.suffix) icon")
                #expect(glyph.hasLightLayer == (set.layers == 2), "\(glyph.iconName)")
                #expect(glyph.layerOpacity > 0 && glyph.layerOpacity <= 1, "\(glyph.iconName)")
                for layer in [GlyphLayer.solid] + (glyph.hasLightLayer ? [.light] : []) {
                    let path = glyph.path(layer)
                    #expect(!path.isEmpty, "\(glyph.iconName) \(layer)")
                    #expect(box.contains(path.boundingRect), "\(glyph.iconName) \(layer) leaves its box: \(path.boundingRect)")
                }
                if !glyph.hasLightLayer { #expect(glyph.path(.light).isEmpty, "\(glyph.iconName) draws a light layer it does not have") }
            }
        }
        // The light layer's opacity per set: Solar's own, and the mock's 25% for Phosphor's (its set gives 20%).
        #expect(SpaceVibeGlyph.allCases.allSatisfy { $0.layerOpacity == 0.5 && $0.outlineWidth == 0 })
        #expect(ContentGlyph.allCases.allSatisfy { $0.layerOpacity == 0.25 && $0.outlineWidth == 0.75 })
        #expect(CategoryGlyph.allCases.allSatisfy { $0.outlineWidth == 0 })
    }

    @Test("category glyphs are the three MingCute Line icons of V5-R10; the rest come from Phosphor")
    func categoryAndContent() {
        let category = Dictionary(uniqueKeysWithValues: CategoryGlyph.allCases.map { (String(describing: $0), $0.iconName) })
        #expect(category == ["skill": "flash-line", "subagent": "robot-line", "hook": "fish-symbol-line"])
        // Rules is the mock's checklist glyph, a Phosphor one (D32 names none); the sidebar glyphs are the mock's.
        let content = Dictionary(uniqueKeysWithValues: ContentGlyph.allCases.map { (String(describing: $0), $0.iconName) })
        #expect(content["rule"] == "list-checks-duotone")
        for (name, icon) in [("stack", "stack"), ("pulse", "pulse"), ("gauge", "gauge"), ("sliders", "sliders-horizontal"), ("search", "magnifying-glass"),
                             ("sun", "sun"), ("moon", "moon"), ("stop", "stop-circle"), ("copy", "copy"), ("bug", "bug")] {
            #expect(content[name] == icon + "-duotone", "\(name)")
        }
        // A name belongs to one family, so a category glyph is never picked from the content set by mistake.
        #expect(Set(content.values).isDisjoint(with: Set(category.values)))
    }

    @Test("verdict glyphs are SpaceVibe's own: five shapes in fg2, in no generated set")
    func verdicts() throws {
        #expect(VerdictGlyph.Kind.allCases.map { String(describing: $0) } == ["heavy", "used", "never", "dead", "nm"])
        let generated = Set(Self.sets.flatMap { $0.glyphs.map { String(describing: $0) } })
        #expect(generated.isDisjoint(with: VerdictGlyph.Kind.allCases.map { String(describing: $0) }))
        let source = try Self.source("Components/VerdictGlyph.swift")
        #expect(!source.contains("SpaceVibeIcon(") && !source.contains("GlyphSource"), "the verdict glyphs are shapes, not generated paths")
        let palette = try NSRegularExpression(pattern: #"Palette\.(\w+)"#).matches(in: source, range: NSRange(source.startIndex..., in: source))
            .map { String(source[Range($0.range(at: 1), in: source)!]) }
        #expect(Set(palette) == ["fg2", "onVerdict"], "D58: one neutral colour, the cut-out in onVerdict; found \(Set(palette))")
    }

    @Test("v5 screen folders draw no Solar glyph")
    func v5ScreensLeaveSolar() throws {
        let solar = try NSRegularExpression(pattern: #"SpaceVibeGlyph|SpaceVibeIcon\(\s*\."#)
        for folder in StyleBoundaryTests.v5Folders {
            let root = Self.appSources.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(atPath: root.path) else { continue }
            for case let relative as String in walker where relative.hasSuffix(".swift") {
                let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
                #expect(solar.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) == 0, "\(folder)/\(relative) uses a Solar glyph")
            }
        }
    }

    @Test("icon sizes: 16, 14, 12 and 24 for v5, the old 22 and 20 until the cut-over, never under 12")
    func sizes() {
        #expect(IconSize.control.points == 16 && IconSize.inline.points == 14 && IconSize.small.points == 12 && IconSize.large.points == 24)
        #expect(IconSize.sidebar.points == 22 && IconSize.row.points == 20)
        for size in IconSize.allCases { #expect(size.points >= 12, "\(size)") }
        #expect(IconSize.allCases.map(\.points).min() == 12)
    }

    @Test("every generated file says where it comes from, and the app credits every set in use")
    func attribution() throws {
        for set in Self.sets where !set.glyphs.isEmpty {
            let data = try Self.source("Components/" + set.file)
            #expect(data.hasPrefix("// Generated by scripts/generate-icons.mjs from \(set.package) "), "\(set.file)")
            #expect(data.contains(set.credit), "\(set.file) header")
            #expect(Credits.text.contains(set.credit), "the About panel credits \(set.credit)")
        }
        #expect(Credits.text.contains("SIL Open Font License"))
        // Section 4(b) of Apache-2.0 and the notices of the others: each header says the paths were changed.
        #expect(try Self.source("Components/CategoryIconData.swift").contains("Changed from the original"))
        #expect(try Self.source("Components/ContentIconData.swift").contains("Changed from the original"))
        #expect(Credits.text.contains("https://creativecommons.org/licenses/by/4.0/"))
    }

    @Test("each licence a set asks for is shown: Solar's link, MIT's notice and the Apache-2.0 text in the bundle")
    func licences() throws {
        #expect(Credits.text.contains("Copyright (c) 2023 Phosphor Icons"))
        #expect(Credits.text.contains("The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."))
        // Apache-2.0 section 4(a): the text itself, in the About panel or as a file the credit names and the build copies.
        if !Credits.text.contains("Apache License\n") {
            let name = "MingCute-Apache-2.0.txt"
            #expect(Credits.text.contains("Licenses/" + name))
            let root = StyleBoundaryTests.appSources.deletingLastPathComponent().deletingLastPathComponent()
            let licence = try String(contentsOf: root.appendingPathComponent("Resources/Licenses/" + name), encoding: .utf8)
            #expect(licence.contains("Apache License") && licence.contains("Version 2.0, January 2004") && licence.contains("4. Redistribution."))
            let script = try String(contentsOf: root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
            #expect(script.contains("Resources/Licenses/*.txt"))
        }
    }
}
