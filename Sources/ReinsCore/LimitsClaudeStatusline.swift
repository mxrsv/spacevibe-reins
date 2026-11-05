import Foundation

/// Claude invokes the separate collector; the app only reads these private, bounded snapshots.
/// Never reads another application's captures or stores the rest of the status-line input.
public enum LimitsClaudeStatusline {
    public static let maxInputBytes = 1 << 20
    static let maxSnapshotBytes = 4096
    static let maxSessions = 64
    static let maximumAge: TimeInterval = 3600
    static let windows = [("five_hour", "five_hour", 300), ("seven_day", "weekly_all", 10080)]

    static func directory(_ roots: Roots) -> URL { roots.data.appendingPathComponent("claude-limits") }

    /// Bind captures to the configured account without persisting its identifiers. No credential is read.
    static func accountKey(_ roots: Roots) -> String? {
        guard case .value(let state) = InventoryFileIO.readJSON(roots.claudeState),
              let account = state["oauthAccount"]?["accountUuid"]?.stringValue, !account.isEmpty else { return nil }
        let organization = state["oauthAccount"]?["organizationUuid"]?.stringValue ?? ""
        return ContentHash.sha256Hex(Data("\(roots.claude.root.standardizedFileURL.path)\n\(account)\n\(organization)".utf8))
    }

    /// A missing quota is normal before the first response. Invalid input never replaces a good snapshot.
    public static func capture(_ data: Data, roots: Roots, now: Date = Date()) throws {
        guard data.count <= maxInputBytes else { throw ReinsError("Status line input is too large.", status: 400) }
        let input = try OrderedJSON(data: data).root
        guard let session = input["session_id"]?.stringValue, !session.isEmpty, session.utf8.count <= 128,
              session.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw ReinsError("Status line session identity is invalid.", status: 400)
        }
        guard let raw = input.limitsMember("rate_limits") else { return }
        let parsed = try parseWindows(raw)
        guard !parsed.isEmpty, let account = accountKey(roots) else { return }
        let folder = try StatuslineSetup.managedDirectory(roots, name: "claude-limits")
        let file = folder.appendingPathComponent("\(session).json")
        // A session first captured under another account cannot relabel its old in-memory quota after a login switch.
        if let old = snapshot(file), old["account"]?.stringValue != account { return }
        let cleanWindows = windows.compactMap { key, _, _ -> JSONMember? in
            guard let window = raw.limitsMember(key) else { return nil }
            return JSONMember(key, .object([
                JSONMember("used_percentage", window["used_percentage"]!), JSONMember("resets_at", window["resets_at"]!),
            ]))
        }
        let clean = JSONValue.object([
            JSONMember("account", .string(account)), JSONMember("observedAt", .number(String(now.timeIntervalSince1970))),
            JSONMember("rate_limits", .object(cleanWindows)),
        ])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try AtomicWrite.write(to: file.path, data: Data(OrderedJSON.pretty(clean).utf8), mode: 0o600)
        for old in files(roots).dropFirst(maxSessions) where snapshot(old)?["account"]?.stringValue != nil {
            try FileManager.default.removeItem(at: old)
        }
    }

    static func files(_ roots: Roots) -> [URL] {
        guard let folder = try? StatuslineSetup.managedDirectory(roots, name: "claude-limits") else { return [] }
        return InventoryFileIO.list(folder).filter { name in
            name.hasSuffix(".json") && name.dropLast(5).utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
            }
        }.map { folder.appendingPathComponent($0) }.filter { url in
            var info = stat()
            return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        }.sorted { (InventoryFileIO.modifiedMs($0) ?? 0) > (InventoryFileIO.modifiedMs($1) ?? 0) }
    }

    static func snapshot(_ file: URL) -> JSONValue? {
        guard let data = InventoryFileIO.readData(file, maxBytes: maxSnapshotBytes + 1), data.count <= maxSnapshotBytes else { return nil }
        return try? OrderedJSON(data: data).root
    }

    static func parseWindows(_ raw: JSONValue) throws -> [LimitWindow] {
        guard raw.objectValue != nil else { throw ReinsError("Invalid status line limits.", status: 400) }
        return try windows.compactMap { key, id, minutes in
            guard let value = raw.limitsMember(key) else { return nil }
            guard let used = value["used_percentage"]?.limitsNumber, (0...100).contains(used),
                  let reset = value["resets_at"]?.limitsNumber, reset > 0, reset < 253_402_300_800,
                  reset.rounded() == reset else { throw ReinsError("Invalid status line window.", status: 400) }
            return LimitWindow(id: id, minutes: minutes, scope: nil, usedPercent: used,
                               resetsAt: Date(timeIntervalSince1970: reset), active: true)
        }
    }

    static func read(_ roots: Roots, now: Date = Date()) -> CLILimits {
        let cached = LimitsClaudeCache.read(roots)
        guard let account = accountKey(roots) else { return cached }
        let readings: [(Date, [LimitWindow])] = files(roots).prefix(maxSessions).compactMap { file in
            guard let data = snapshot(file), data["account"]?.stringValue == account,
                  let seconds = data["observedAt"]?.limitsNumber, seconds > 0, seconds <= now.timeIntervalSince1970,
                  let raw = data["rate_limits"], let windows = try? parseWindows(raw), !windows.isEmpty else { return nil }
            return (Date(timeIntervalSince1970: seconds), windows)
        }.sorted { $0.0 > $1.0 }
        guard let newest = readings.first else { return cached }
        if case .measured(let at, _) = cached.state, at > newest.0 { return cached }
        // An idle session can repeat an older percentage after an active session. Within the same reset window,
        // use the highest recent observation so receiving that old session's status line cannot move usage backwards.
        let recent = readings.filter { newest.0.timeIntervalSince($0.0) <= maximumAge }
        let merged: [LimitWindow] = windows.compactMap { _, id, _ in
            guard let window = recent.lazy.flatMap(\.1).first(where: { $0.id == id }) else { return nil }
            return recent.flatMap(\.1)
                .filter { $0.id == window.id && $0.resetsAt == window.resetsAt }
                .max { $0.usedPercent < $1.usedPercent } ?? window
        }
        return CLILimits(cli: .claude, state: .measured(at: newest.0, windows: merged), source: .claudeStatusline)
    }
}
