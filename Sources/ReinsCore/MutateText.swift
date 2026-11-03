import Foundation

/// Text formats of the Node core, spelled the same way: `JSON.stringify` strings, the agent files of both CLIs.
enum MutateText {
    /// `JSON.stringify(text)`: a double-quoted string, which is also valid YAML and TOML for what the CLIs read.
    static func quote(_ text: String) -> String {
        (try? OrderedJSON.pretty(.string(text), trailingNewline: false)) ?? "\"\""
    }

    /// The `description` value of a generated header: one line, quoted.
    static func yamlValue(_ text: String) -> String { quote(ActivityText.squash(text)) }

    /// A new agent file in the format of its CLI: markdown with a header for Claude Code, TOML for Codex.
    static func agentText(cli: InventoryCLI, name: String, description: String, instructions: String) -> String {
        switch cli {
        case .claude:
            return "---\nname: \(name)\ndescription: \(yamlValue(description))\n---\n\n\(ActivityText.trim(instructions))\n"
        case .codex:
            return "name = \(quote(name))\ndescription = \(quote(description))\ndeveloper_instructions = \(quote(ActivityText.trim(instructions)))\n"
        }
    }

    static func skillText(name: String, description: String, body: String) -> String {
        "---\nname: \(name)\ndescription: \(yamlValue(description))\n---\n\n\(ActivityText.trim(body))\n"
    }

    /// What an agent file says, as the Node copy reads it: markdown header plus body, or the TOML keys.
    static func agentFields(isTOML: Bool, text: String) -> (description: String, instructions: String) {
        if isTOML {
            return (Inventory.tomlFields(text)["description"] ?? "", tomlInstructions(text))
        }
        return (Frontmatter.parse(text)["description"] ?? "", stripHeader(text))
    }

    private static let blockInstructions = try! NSRegularExpression(
        pattern: #"^developer_instructions\s*=\s*("""|''')([\s\S]*?)\1"#, options: [.anchorsMatchLines]
    )
    private static let lineInstructions = try! NSRegularExpression(
        pattern: #"^developer_instructions\s*=\s*("(?:[^"\\]|\\.)*")"#, options: [.anchorsMatchLines]
    )
    private static let header = try! NSRegularExpression(pattern: #"\A---\r?\n[\s\S]*?\r?\n---\r?\n?"#)

    /// `developer_instructions` of a Codex agent: a triple-quoted block as written (one leading newline dropped), or a one-line string.
    /// Escapes inside a block are kept as written, like the Node regex does.
    static func tomlInstructions(_ text: String) -> String {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        if let match = blockInstructions.firstMatch(in: text, range: all) {
            var body = String.UnicodeScalarView(ns.substring(with: match.range(at: 2)).unicodeScalars)
            if body.first == "\n" { body.removeFirst() }
            return String(body)
        }
        if let match = lineInstructions.firstMatch(in: text, range: all) {
            return Frontmatter.unquote(ns.substring(with: match.range(at: 1)))
        }
        return ""
    }

    /// The text after the `---` header, or the whole text when there is none.
    static func stripHeader(_ text: String) -> String {
        let ns = text as NSString
        guard let match = header.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return text }
        return ns.substring(from: match.range.upperBound)
    }
}
