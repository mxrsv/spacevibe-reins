import Foundation

/// A model named in a CLI's session logs and how many sessions used it.
public struct ModelCount: Equatable, Sendable, Identifiable {
    public let model: String
    public let sessions: Int

    public var id: String { model }
}

/// The models the Model panel offers as chips (spec, Interface: Model): the first model each recent session log names,
/// counted per session. Claude Code writes it on each assistant message (`message.model`), Codex on `turn_context`. Logs are
/// found through `LogFiles`, so Codex's `.jsonl.zst` rollouts count too. Only the model name is read from a line.
public enum ModelUsage {
    /// How many logs are read, newest first, and how far into each.
    static let logLimit = 400
    static let lineLimit = 200

    private struct Found: Error {
        let model: String
    }

    public static func seen(_ roots: Roots, cli: InventoryCLI) -> [ModelCount] {
        let folder = cli == .claude ? roots.claude.logs : roots.codex.logs
        let logs = LogFiles.walk(folder)
            .map { url in (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(logLimit)
        var counts: [String: Int] = [:]
        for (url, _) in logs {
            if let model = firstModel(url) { counts[model, default: 0] += 1 }
        }
        return counts.map { ModelCount(model: $0.key, sessions: $0.value) }
            .sorted { $0.sessions != $1.sessions ? $0.sessions > $1.sessions : $0.model < $1.model }
    }

    static func firstModel(_ url: URL) -> String? {
        var lines = 0
        do {
            try LogFiles.forEachLine(at: url, maxLineBytes: 1 << 20) { line in
                lines += 1
                if let model = model(in: line) { throw Found(model: model) }
                if lines >= lineLimit { throw Found(model: "") }
            }
        } catch let found as Found {
            return found.model.isEmpty ? nil : found.model
        } catch {
            return nil
        }
        return nil
    }

    /// The value after the first `"model":"` in a line, when it looks like a model name.
    static func model(in line: Data) -> String? {
        let key = Array("\"model\":\"".utf8)
        let bytes = [UInt8](line)
        guard bytes.count > key.count else { return nil }
        var i = 0
        while i + key.count <= bytes.count {
            if bytes[i] == key[0], Array(bytes[i..<(i + key.count)]) == key {
                var j = i + key.count
                while j < bytes.count, bytes[j] != 0x22, j - i < 120 { j += 1 }
                guard j < bytes.count, bytes[j] == 0x22, j > i + key.count else { return nil }
                let name = String(decoding: bytes[(i + key.count)..<j], as: UTF8.self)
                let allowed = name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-._:/[]".unicodeScalars.contains($0) }
                return allowed && name != "<synthetic>" ? name : nil
            }
            i += 1
        }
        return nil
    }
}
