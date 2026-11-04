import Foundation
import SwiftUI
import Testing
@testable import Reins

/// Every icon comes from a generated set (spec `docs/specs/2026-11-03-reins-design-language.md`, v3 "Icons" and v4 "Two
/// icon sets, split by job", DL7): no SF Symbol outside `Gallery/`, no other image except the CLI brand marks, Solar only in
/// the sidebar and Tabler everywhere else, every glyph inside its 24 pt box, no size under 14, and both licences in the app.
@Suite("Icon policy: Solar in the sidebar, Tabler in pages")
struct IconPolicyTests {
    static var appSources: URL { StyleBoundaryTests.appSources }

    /// The sidebar's items and footer: the only files that draw Solar, and they never draw Tabler.
    static let sidebarFiles: Set<String> = [
        "Shell/SidebarView.swift", "Shell/ThemeToggle.swift", "Components/SidebarItem.swift",
        "Components/LimitSidebarTile.swift", "Limits/LimitsSidebarBlock.swift",
    ]
    /// Files that name the Solar type without drawing it: the set itself, and each tab naming its sidebar icon.
    static let solarDeclarations: Set<String> = [
        "Components/ReinsIcon.swift", "Components/ReinsIconData.swift", "Shell/ReinsTab.swift",
        "Loadout/LoadoutTab.swift", "Rules/RulesTab.swift", "Activity/ActivityTab.swift", "Agents/AgentsTab.swift",
    ]
    static let solarPattern = #"\bReinsIcon\(|\bReinsGlyph\b"#
    static let tablerPattern = #"\bPageIcon\(|\bPageGlyph\b|\bChevron\("#

    /// Lines of code (whole-line comments skipped) matching `pattern`, per file under `Sources/Reins`, `Gallery/` exempt.
    static func matches(_ pattern: String) throws -> [String: Int] {
        let regex = try NSRegularExpression(pattern: pattern)
        var result: [String: Int] = [:]
        let root = appSources.path + "/"
        guard let walker = FileManager.default.enumerator(atPath: appSources.path) else { return result }
        for case let relative as String in walker where relative.hasSuffix(".swift") && !relative.hasPrefix("Gallery/") {
            let source = try String(contentsOfFile: root + relative, encoding: .utf8)
            var count = 0
            for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("//") { continue }
                count += regex.numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line))
            }
            if count > 0 { result[relative] = count }
        }
        return result
    }

    @Test("Solar is drawn only in the sidebar, and named only by the set and the tabs' sidebar icons")
    func solarInSidebarOnly() throws {
        let found = try Self.matches(Self.solarPattern)
        let outside = found.keys.filter { !Self.sidebarFiles.contains($0) && !Self.solarDeclarations.contains($0) }.sorted()
        #expect(outside.isEmpty, "Solar outside the sidebar: \(outside.joined(separator: ", ")). Use PageIcon.")
        // The walk itself found the sidebar: it draws Solar.
        #expect(found["Shell/SidebarView.swift"] != nil && found["Components/SidebarItem.swift"] != nil)
    }

    @Test("the sidebar never draws a Tabler glyph")
    func noTablerInSidebar() throws {
        let found = try Self.matches(Self.tablerPattern)
        let inSidebar = found.keys.filter { Self.sidebarFiles.contains($0) }.sorted()
        #expect(inSidebar.isEmpty, "Tabler in the sidebar: \(inSidebar.joined(separator: ", ")). Use ReinsIcon.")
        // Pages do draw it.
        #expect(found["Components/Tag.swift"] != nil && found["Components/ReinsButtonStyle.swift"] != nil)
    }

    @Test("the split patterns catch what they name")
    func splitPatterns() throws {
        let solar = try NSRegularExpression(pattern: Self.solarPattern)
        let tabler = try NSRegularExpression(pattern: Self.tablerPattern)
        func count(_ regex: NSRegularExpression, _ text: String) -> Int { regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) }
        #expect(count(solar, "ReinsIcon(.settings)") == 1)
        #expect(count(solar, "let icon = ReinsGlyph.loadout") == 1)
        #expect(count(solar, "PageIcon(.settings)") == 0)
        #expect(count(tabler, "PageIcon(.trash)") == 1)
        #expect(count(tabler, "var icon: PageGlyph?") == 1)
        #expect(count(tabler, "Chevron(.upDown)") == 1)
        #expect(count(tabler, "ReinsIcon(.sun)") == 0)
    }

    /// What only the generated set may draw. `Image(` is allowed in `brandMarkFile` (the CLI marks are images, not icons).
    static let forbidden: [(name: String, pattern: String)] = [
        ("SF Symbol", #"systemName:|systemImage:|systemSymbolName"#),
        ("image", #"\bImage\("#),
    ]
    static let brandMarkFile = "Components/CLIMark.swift"

    /// Matches per file under `Sources/Reins`, `Gallery/` exempt. Whole-line comments are skipped.
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
    func solarOnly() throws {
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
        #expect(count(image, "ReinsIcon(.trash)") == 0)
        #expect(count(image, "ImageRenderer(content: view)") == 0)
    }

    @Test("every glyph has both layers, inside its 24 pt box, from a Bold Duotone icon")
    func glyphs() {
        #expect(!ReinsGlyph.allCases.isEmpty)
        let box = CGRect(x: 0, y: 0, width: ReinsGlyph.box, height: ReinsGlyph.box).insetBy(dx: -0.5, dy: -0.5)
        for glyph in ReinsGlyph.allCases {
            #expect(glyph.solarName.hasSuffix("-bold-duotone"), "\(glyph)")
            for layer in [GlyphLayer.solid, .light] {
                let path = glyph.path(layer)
                #expect(!path.isEmpty, "\(glyph) \(layer)")
                #expect(box.contains(path.boundingRect), "\(glyph) \(layer) leaves its box: \(path.boundingRect)")
            }
        }
        #expect(ReinsGlyph.lightOpacity == 0.5)
        #expect(Set(ReinsGlyph.allCases.map(\.solarName)).count == ReinsGlyph.allCases.count)
    }

    @Test("every page glyph is one stroked path inside its 24 pt box, from a distinct Tabler icon")
    func pageGlyphs() {
        #expect(!PageGlyph.allCases.isEmpty)
        let box = CGRect(x: 0, y: 0, width: PageGlyph.box, height: PageGlyph.box).insetBy(dx: -0.5, dy: -0.5)
        for glyph in PageGlyph.allCases {
            var pen = GlyphPen()
            glyph.draw(into: &pen)
            #expect(!pen.path.isEmpty, "\(glyph)")
            #expect(box.contains(pen.path.boundingRect), "\(glyph) leaves its box: \(pen.path.boundingRect)")
        }
        #expect(PageGlyph.box == 24 && PageGlyph.stroke == 2)
        #expect(Set(PageGlyph.allCases.map(\.tablerName)).count == PageGlyph.allCases.count)
    }

    @Test("icon sizes are 22, 20, 16 and 14, never smaller")
    func sizes() {
        #expect(IconSize.sidebar.points == 22 && IconSize.row.points == 20 && IconSize.control.points == 16 && IconSize.inline.points == 14)
        for size in [IconSize.sidebar, .row, .control, .inline, .large] { #expect(size.points >= 14) }
    }

    @Test("the generated data says where it comes from, and the app credits Solar under CC BY 4.0 and Tabler under MIT")
    func attribution() throws {
        let data = try String(contentsOf: Self.appSources.appendingPathComponent("Components/ReinsIconData.swift"), encoding: .utf8)
        #expect(data.hasPrefix("// Generated by scripts/generate-icons.mjs"))
        #expect(data.contains("Solar by 480 Design, CC BY 4.0"))
        #expect(Credits.text.contains("Solar by 480 Design, CC BY 4.0"))
        #expect(Credits.text.contains("https://creativecommons.org/licenses/by/4.0/"))
        #expect(Credits.text.contains("SIL Open Font License"))
        let pageData = try String(contentsOf: Self.appSources.appendingPathComponent("Components/PageIconData.swift"), encoding: .utf8)
        #expect(pageData.hasPrefix("// Generated by scripts/generate-icons.mjs from @iconify-json/tabler"))
        #expect(pageData.contains("Tabler Icons by Paweł Kuna, MIT"))
        #expect(Credits.text.contains("Tabler Icons"))
        #expect(Credits.text.contains("Copyright (c) 2020-2026 Paweł Kuna"))
        #expect(Credits.text.contains("The above copyright notice and this permission notice shall be included"))
    }
}
