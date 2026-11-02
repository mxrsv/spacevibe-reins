import Foundation
import Testing
@testable import ReinsCore

@Suite("Frontmatter")
struct FrontmatterTests {
    @Test("plain, double-quoted and single-quoted values")
    func scalars() {
        let text = "---\nname: ponytail\ndescription: \"Say \\\"hi\\\" \\u00e9\"\ntitle: 'it''s fine'\nmodel: sonnet\n---\nbody"
        let fm = Frontmatter.parse(text)
        #expect(fm["name"] == "ponytail")
        #expect(fm["description"] == "Say \"hi\" é")
        #expect(fm["title"] == "it's fine")
        #expect(fm["model"] == "sonnet")
    }

    @Test("a folded > block joins its lines with spaces")
    func folded() {
        let fm = Frontmatter.parse("---\nname: keep\ndescription: >\n  folded\n  text\n\n  more\nnext: x\n---\nbody")
        #expect(fm["description"] == "folded text  more")
        #expect(fm["next"] == "x")
    }

    @Test("a literal | block keeps newlines; strip and keep markers are accepted")
    func literal() {
        let fm = Frontmatter.parse("---\na: |\n  one\n  two\nb: >-\n  x\n  y\nc: |+\n  z\n---\n")
        #expect(fm["a"] == "one\ntwo")
        #expect(fm["b"] == "x y")
        #expect(fm["c"] == "z")
    }

    @Test("CRLF files read the same")
    func crlf() {
        let fm = Frontmatter.parse("---\r\nname: x\r\ndescription: >\r\n  a\r\n  b\r\n---\r\nbody")
        #expect(fm["name"] == "x")
        #expect(fm["description"] == "a b")
    }

    @Test("no header, an unterminated header or an empty header give no fields")
    func missing() {
        #expect(Frontmatter.parse("# just markdown\n").isEmpty)
        #expect(Frontmatter.parse("---\nname: x\n").isEmpty)
        #expect(Frontmatter.parse("---\n---\n").isEmpty)
        #expect(Frontmatter.parse("\n---\nname: x\n---\n").isEmpty)
        #expect(Frontmatter.parse("").isEmpty)
    }

    @Test("indented lines, lists and keys that do not start with a letter are ignored")
    func ignoresNonFlat() {
        let fm = Frontmatter.parse("---\nname: a\ntools:\n  - Read\n  - Edit\n1bad: x\n  nested: y\nlast: z\n---\n")
        #expect(fm["name"] == "a")
        #expect(fm["tools"] == "")
        #expect(fm["last"] == "z")
        #expect(fm["nested"] == nil)
        #expect(fm["1bad"] == nil)
    }

    @Test("a colon inside the value is kept; the last duplicate key wins; keys may hold dashes")
    func colonsAndDuplicates() {
        let fm = Frontmatter.parse("---\nargument-hint: <a: b>\nname: first\nname: second\nurl: http://x/y\n---\n")
        #expect(fm["argument-hint"] == "<a: b>")
        #expect(fm["name"] == "second")
        #expect(fm["url"] == "http://x/y")
    }

    @Test("a malformed double-quoted value drops its first and last character, like the Node reader")
    func malformedQuote() {
        #expect(Frontmatter.parse("---\nname: \"abc\" trailing\n---\n")["name"] == "abc\" trailin")
    }

    @Test("the fixture skills and agents read")
    func fixture() throws {
        let skill = try String(contentsOf: Fixtures.url("home/.claude/skills/ponytail/SKILL.md"), encoding: .utf8)
        let fm = Frontmatter.parse(skill)
        #expect(fm["name"] == "ponytail")
        #expect(fm["description"] == "Pick the laziest solution that works")
    }
}
