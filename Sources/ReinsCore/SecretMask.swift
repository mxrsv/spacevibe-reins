import Foundation

/// Secret values in the settings files the Agents page shows (spec `docs/specs/2026-11-05-reins-agents.md`, Writes:
/// Secrets; AGENTS.md S-R3). Two rules, picked by the owner on 2026-11-05:
///
/// - every value of an MCP server's environment and headers: `mcpServers.<name>.env` and `.headers` in Claude Code's JSON,
///   `mcp_servers.<name>.env`, `.http_headers` and `.env_http_headers` in Codex's TOML;
/// - elsewhere, any value whose key name contains `key`, `token`, `secret`, `password` or `auth`, in any case (Claude's
///   `env`, Codex's `shell_environment_policy.set`). An array element takes its array's key name.
///
/// Every other value shows as it is. A masked value reads `••••`. `MaskedText` keeps the originals inside `ReinsCore`: the
/// UI gets the masked text and a count, never a secret, and `unmask` puts each original back where its placeholder still
/// sits, refusing a placeholder that moved to another key.
public enum SecretMask {
    /// What the UI shows in place of a secret.
    public static let placeholder = "\u{2022}\u{2022}\u{2022}\u{2022}"
    static let words = ["key", "token", "secret", "password", "auth"]

    /// Whether a key name marks its value as secret.
    public static func isSecretName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return words.contains { lower.contains($0) }
    }

    /// Whether the value at `path` in a Claude Code JSON file (settings, `.mcp.json`, `~/.claude.json`) is secret. Array
    /// indexes are written `[0]`.
    public static func isSecretJSON(_ path: [String]) -> Bool {
        isSecret(path, servers: "mcpServers", tables: ["env", "headers"])
    }

    /// Whether the value at `path` (table plus dotted key) in Codex's `config.toml` is secret.
    public static func isSecretTOML(_ path: [String]) -> Bool {
        isSecret(path, servers: "mcp_servers", tables: ["env", "http_headers", "env_http_headers"])
    }

    private static func isSecret(_ path: [String], servers: String, tables: Set<String>) -> Bool {
        // [..., servers, <name>, <table>, <key>...]: the value sits below one of the server's secret tables.
        for (index, part) in path.enumerated() where part == servers && index + 3 < path.count && tables.contains(path[index + 2]) {
            return true
        }
        guard let name = path.last(where: { !($0.hasPrefix("[") && $0.hasSuffix("]")) }) else { return false }
        return isSecretName(name)
    }

    static func refusalMoved() -> ReinsError {
        ReinsError("A hidden value (\(placeholder)) is no longer under its key. Put it back where it was, or type a new value. Nothing was saved.", status: 409)
    }

    // MARK: Masking

    /// A JSON file with every secret value replaced by `"••••"`. Throws when the file is not valid JSON, without content.
    public static func maskJSON(_ text: String) throws -> MaskedText {
        try maskJSON(text, onDisk: text)
    }

    /// `onDisk` is what the file holds, for the check a save makes; a blank file is shown as `{}`.
    static func maskJSON(_ text: String, onDisk: String) throws -> MaskedText {
        let document: OrderedJSON
        do { document = try OrderedJSON(text: text) } catch { throw ReinsError("The file is not valid JSON.", status: 409) }
        var spans: [(path: [String], range: Range<Int>)] = []
        collectJSON(document.tree, path: [], into: &spans)
        return MaskedText(format: .json, original: document.bytes, spans: spans.filter { isSecretJSON($0.path) }, onDisk: Array(onDisk.utf8))
    }

    /// Codex's `config.toml` with every secret value replaced by `"••••"`.
    public static func maskTOML(_ text: String) -> MaskedText {
        let layout = TOMLLayout(text: text)
        var spans: [(path: [String], range: Range<Int>)] = []
        for statement in layout.statements {
            for leaf in layout.leaves(in: statement.value) {
                spans.append((statement.path + leaf.path, leaf.range))
            }
        }
        return MaskedText(format: .toml, original: layout.bytes, spans: spans.filter { isSecretTOML($0.path) })
    }

    /// A settings file read and masked inside the engine, so the raw text never reaches the app. A missing or blank file
    /// reads as `{}`. Throws when it is not valid JSON.
    public static func maskJSONFile(_ url: URL) throws -> MaskedText {
        let text = InventoryFileIO.readText(url, maxBytes: InventoryFileIO.maxJSONBytes) ?? ""
        return try maskJSON(text.allSatisfy(\.isWhitespace) ? "{\n}\n" : text, onDisk: text)
    }

    /// Codex's `config.toml` read and masked inside the engine. A missing file reads as empty.
    public static func maskTOMLFile(_ url: URL) -> MaskedText {
        maskTOML(InventoryFileIO.readText(url, maxBytes: InventoryFileIO.maxJSONBytes) ?? "")
    }

    static func collectJSON(_ node: JSONNode, path: [String], into out: inout [(path: [String], range: Range<Int>)]) {
        switch node {
        case .scalar(_, let range): out.append((path, range))
        case .array(let items, _):
            for (index, item) in items.enumerated() { collectJSON(item, path: path + ["[\(index)]"], into: &out) }
        case .object(let members, _):
            for member in members { collectJSON(member.value, path: path + [member.key], into: &out) }
        }
    }
}

/// A settings file with its secrets masked. `text` is what the Advanced editor shows; the originals never leave
/// `ReinsCore`.
public struct MaskedText: Sendable {
    enum Format: Sendable {
        case json, toml
    }

    let format: Format
    /// The original literal (quotes included) of each secret, by path.
    let secrets: [[String]: [UInt8]]
    public let text: String
    /// The SHA-256 of the bytes that were masked, so a save can tell the file changed since.
    let originalDigest: String
    /// How many values are hidden.
    public var hiddenCount: Int { secrets.count }

    init(format: Format, original: [UInt8], spans: [(path: [String], range: Range<Int>)], onDisk: [UInt8]? = nil) {
        self.format = format
        originalDigest = ContentHash.sha256Hex(Data(onDisk ?? original))
        var secrets: [[String]: [UInt8]] = [:]
        var bytes = original
        let literal = Array("\"\(SecretMask.placeholder)\"".utf8)
        for span in spans.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            secrets[span.path] = Array(original[span.range])
            bytes.replaceSubrange(span.range, with: literal)
        }
        self.secrets = secrets
        text = String(decoding: bytes, as: UTF8.self)
    }

    /// The edited text with every placeholder still under its own key turned back into the original bytes. A secret that
    /// was deleted or retyped stays as edited. Throws when a placeholder sits under a key that held no secret, or when a
    /// JSON file no longer parses (with the line, never the content).
    public func unmask(_ edited: String) throws -> String {
        var placeholders: [(path: [String], range: Range<Int>)] = []
        let bytes: [UInt8]
        switch format {
        case .json:
            let document: OrderedJSON
            do { document = try OrderedJSON(text: edited) } catch let error as OrderedJSONError {
                if case .syntax(_, let line, _) = error { throw ReinsError("The file is not valid JSON at line \(line).", status: 400) }
                throw ReinsError("The file is not valid JSON.", status: 400)
            }
            var spans: [(path: [String], range: Range<Int>)] = []
            SecretMask.collectJSON(document.tree, path: [], into: &spans)
            placeholders = spans.filter { document.bytes[$0.range].elementsEqual(Self.literal) }
            bytes = document.bytes
        case .toml:
            let layout = TOMLLayout(text: edited)
            for statement in layout.statements {
                for leaf in layout.leaves(in: statement.value) where layout.bytes[leaf.range].elementsEqual(Self.literal) {
                    placeholders.append((statement.path + leaf.path, leaf.range))
                }
            }
            bytes = layout.bytes
        }
        var out = bytes
        for item in placeholders.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            guard let original = secrets[item.path] else { throw SecretMask.refusalMoved() }
            out.replaceSubrange(item.range, with: original)
        }
        return String(decoding: out, as: UTF8.self)
    }

    static let literal = Array("\"\(SecretMask.placeholder)\"".utf8)
}
