import Foundation
@testable import ReinsCore

/// Synthetic log lines in the shapes Claude Code and Codex write usage. Nothing is copied from a real log; names and
/// numbers are made up (AGENTS.md S-R2).
enum TokenLines {
    struct Kinds {
        var input = 0
        var output = 0
        var cacheWrite = 0
        var cacheWrite1h = 0
        var cacheRead = 0
    }

    static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    /// A Claude Code assistant record. `model: nil` leaves the model out; `at: nil` leaves the timestamp out.
    static func claude(_ at: String?, model: String? = "claude-opus-5-5", id: String, _ k: Kinds, cwd: String? = nil, sidechain: Bool = false) -> String {
        var usage: [String: Any] = [
            "input_tokens": k.input, "output_tokens": k.output, "cache_creation_input_tokens": k.cacheWrite, "cache_read_input_tokens": k.cacheRead,
        ]
        if k.cacheWrite1h > 0 { usage["cache_creation"] = ["ephemeral_1h_input_tokens": k.cacheWrite1h, "ephemeral_5m_input_tokens": k.cacheWrite - k.cacheWrite1h] }
        var message: [String: Any] = ["id": id, "role": "assistant", "content": [["type": "text", "text": "Done."]], "usage": usage]
        if let model { message["model"] = model }
        var record: [String: Any] = ["type": "assistant", "uuid": "u-\(id)", "isSidechain": sidechain, "message": message]
        if let at { record["timestamp"] = at }
        if let cwd { record["cwd"] = cwd }
        return json(record)
    }

    static func claudeUser(_ at: String, text: String, cwd: String? = nil) -> String {
        var record: [String: Any] = ["type": "user", "timestamp": at, "message": ["role": "user", "content": text]]
        if let cwd { record["cwd"] = cwd }
        return json(record)
    }

    static func codexMeta(_ at: String, id: String, cwd: String) -> String {
        json(["timestamp": at, "type": "session_meta", "payload": ["id": id, "cwd": cwd, "timestamp": at]])
    }

    static func codexTurn(_ at: String, model: String, cwd: String? = nil) -> String {
        var payload: [String: Any] = ["model": model]
        if let cwd { payload["cwd"] = cwd }
        return json(["timestamp": at, "type": "turn_context", "payload": payload])
    }

    /// A Codex `token_count` event. Input counts include their cached part, as Codex logs them.
    static func codexCount(_ at: String, total: (input: Int, cached: Int, output: Int), last: (input: Int, cached: Int, output: Int)? = nil) -> String {
        func usage(_ t: (input: Int, cached: Int, output: Int)) -> [String: Any] {
            ["input_tokens": t.input, "cached_input_tokens": t.cached, "output_tokens": t.output, "reasoning_output_tokens": 0, "total_tokens": t.input + t.output]
        }
        var info: [String: Any] = ["total_token_usage": usage(total)]
        if let last { info["last_token_usage"] = usage(last) }
        return json(["timestamp": at, "type": "event_msg", "payload": ["type": "token_count", "info": info]])
    }

    /// Whole hours since 1970 of an ISO 8601 timestamp.
    static func hour(_ iso: String) -> Int {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
        return Int((date.timeIntervalSince1970 / 3600).rounded(.down))
    }

    static let rolloutId = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"
}
