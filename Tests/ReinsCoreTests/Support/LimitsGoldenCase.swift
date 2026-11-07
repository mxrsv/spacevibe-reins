import Foundation
@testable import ReinsCore

/// One named Limits scenario: the files to put in an empty home, a fixed `now`, and (through `record`) what `Limits.read` says.
/// The inputs are plain data, so they go into limits.json and the Go test recreates the same home from them.
struct LimitsGoldenCase {
    struct File {
        var path: String
        var text: String?
        /// A file of `count` copies of `text`, for the oversized snapshot.
        var repeating: (text: String, count: Int)?
        /// Seconds since 1970; the case's `now` when nil. Log and snapshot order depends on it, so no case leaves it to the clock.
        var mtime: Double?
    }

    static let defaultNow = 1_793_900_000.0
    static let accountToken = "$ACCOUNT_KEY("

    var name: String
    var now = LimitsGoldenCase.defaultNow
    var unsetClaudeConfigDir = false
    var dirs: [String] = []
    var files: [File] = []
    var fifos: [String] = []

    // MARK: Record

    func record() throws -> CanonicalJSON {
        let home = try TempHome()
        var env = home.env
        if unsetClaudeConfigDir { env["CLAUDE_CONFIG_DIR"] = nil }
        let roots = try Roots.resolve(env: env)
        for dir in dirs { try FileManager.default.createDirectory(at: home.url(dir), withIntermediateDirectories: true) }
        for file in files {
            let text = Self.resolveAccounts(in: file.text ?? "", claudeRoot: roots.claude.root)
            let data = file.repeating.map { Data(String(repeating: $0.text, count: $0.count).utf8) } ?? Data(text.utf8)
            let url = try home.write(file.path, data)
            let when = Date(timeIntervalSince1970: file.mtime ?? now)
            try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path)
        }
        for fifo in fifos {
            try FileManager.default.createDirectory(at: home.url(fifo).deletingLastPathComponent(), withIntermediateDirectories: true)
            precondition(mkfifo(home.url(fifo).path, 0o600) == 0, "mkfifo \(fifo)")
        }
        let date = Date(timeIntervalSince1970: now)
        let result = Limits.read(roots, now: date).map { Self.json($0, now: date) }
        return CanonicalJSON.object([
            "name": .string(name),
            "now": .number(now),
            "input": [
                "unsetClaudeConfigDir": .bool(unsetClaudeConfigDir),
                "dirs": .array(dirs.sorted().map(CanonicalJSON.string)),
                "files": .array(files.map { file in
                    var member: [String: CanonicalJSON] = ["path": .string(file.path), "mtime": .number(file.mtime ?? now)]
                    if let text = file.text { member["text"] = .string(text) }
                    if let repeated = file.repeating { member["repeat"] = ["text": .string(repeated.text), "count": .number(Double(repeated.count))] }
                    return .object(member)
                }),
                "fifos": .array(fifos.map(CanonicalJSON.string)),
            ],
            "result": .array(result),
        ]).replacingHome(home.root.path)
    }

    /// `$ACCOUNT_KEY(a,o)` becomes the key the collector derives for account `a` and organization `o` in this home.
    static func resolveAccounts(in text: String, claudeRoot: URL) -> String {
        var out = text
        while let start = out.range(of: accountToken), let end = out[start.upperBound...].firstIndex(of: ")") {
            let parts = out[start.upperBound..<end].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let key = ContentHash.sha256Hex(Data("\(claudeRoot.standardizedFileURL.path)\n\(parts[0])\n\(parts[1])".utf8))
            out.replaceSubrange(start.lowerBound...end, with: key)
        }
        return out
    }

    private static func json(_ limits: CLILimits, now: Date) -> CanonicalJSON {
        var state = "", at: CanonicalJSON = nil, windows: [CanonicalJSON] = []
        switch limits.state {
        case .measured(let taken, let list):
            state = "measured"
            at = .number(taken.timeIntervalSince1970)
            windows = list.map { window in
                [
                    "id": .string(window.id),
                    "minutes": window.minutes.map { .number(Double($0)) } ?? nil,
                    "scope": window.scope.map(CanonicalJSON.string) ?? nil,
                    "usedPercent": .number(window.usedPercent),
                    "resetsAt": .number(window.resetsAt.timeIntervalSince1970),
                    "active": .bool(window.active),
                    "current": .bool(window.isCurrent(at: now)),
                ]
            }
        case .notRecorded: state = "notRecorded"
        case .unreadable: state = "unreadable"
        case .notMeasurable: state = "notMeasurable"
        case .notInstalled: state = "notInstalled"
        }
        return [
            "cli": .string(limits.cli.rawValue),
            "state": .string(state),
            "at": at,
            "windows": .array(windows),
            "plan": limits.plan.map(CanonicalJSON.string) ?? nil,
            "source": limits.source.map { .string($0 == .claudeCache ? "claudeCache" : "claudeStatusline") } ?? nil,
        ]
    }
}
