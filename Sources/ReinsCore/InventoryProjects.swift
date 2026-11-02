import Foundation

// Project discovery. Claude Code keeps no list of projects, so Reins looks where a path is already recorded:
//  - the `cwd` in the head of the newest session logs of each folder under claude/projects (the folder name is a lossy
//    encoding of the path and cannot be decoded), and
//  - the `[projects."<path>"]` tables of Codex config.toml.
// A path counts only if it still exists (or cannot be checked: then it is listed and reported as not readable) and has a `.claude` folder of its own. The home folder is skipped (its `.claude` is
// the global one), and so are paths inside `.claude/worktrees/` (copies of a project already listed).
// Bounded: at most 3 log files per folder, 64 KB each, at most `Inventory.maxProjects` folders, newest first.
// Trade-off: a project never opened with either CLI is not found, and one whose first records fall outside the first 64 KB
// of its 3 newest logs is missed.
extension Inventory {
    static let projectHeadBytes = 64 * 1024
    static let projectLogsPerFolder = 3
    private static let cwdPattern = try! NSRegularExpression(pattern: #""cwd":"((?:[^"\\]|\\.)*)""#)

    /// Absolute paths of the projects that have their own `.claude` folder.
    public static func discoverProjects(roots r: Roots) -> [String] {
        let globalClaude = InventoryFileIO.realPath(r.claude.root.path)
        var seen: [String] = []
        var known = Set<String>()
        let candidates = logCwds(r.claude.logs) + codexProjectKeys(r.codex.root.appendingPathComponent("config.toml"))
        for path in candidates {
            guard path.hasPrefix("/"), !path.contains("/.claude/worktrees/") else { continue }
            let dir = URL(fileURLWithPath: InventoryFileIO.join(path, ".claude"), isDirectory: true)
            // A `.claude` that cannot be looked up (a denied parent) is kept: `read` reports the project as not readable.
            let there = InventoryFileIO.isDirectory(dir) || InventoryFileIO.presence(dir.path) == .unknown
            guard there, InventoryFileIO.realPath(dir.path) != globalClaude else { continue }
            let resolved = InventoryFileIO.normalize(path)
            if known.insert(resolved).inserted { seen.append(resolved) }
            if seen.count >= maxProjects { break }
        }
        return seen
    }

    private static func logCwds(_ logsDir: URL) -> [String] {
        var found: [(path: String, mtime: Double, folder: String)] = []
        for folder in InventoryFileIO.list(logsDir) {
            let base = logsDir.appendingPathComponent(folder, isDirectory: true)
            let logs = InventoryFileIO.list(base).filter { $0.hasSuffix(".jsonl") }.compactMap { name -> (URL, Double)? in
                let url = base.appendingPathComponent(name)
                return InventoryFileIO.modifiedMs(url).map { (url, $0) }
            }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lastPathComponent < $1.0.lastPathComponent }.prefix(projectLogsPerFolder)
            for (url, mtime) in logs {
                guard let cwd = cwdInHead(of: url) else { continue }
                if let path = cwd { found.append((path, mtime, folder)) }
                break
            }
        }
        found.sort { $0.mtime != $1.mtime ? $0.mtime > $1.mtime : $0.folder < $1.folder }
        return found.prefix(maxProjects).map(\.path)
    }

    /// nil: no `"cwd"` in the head. .some(nil): a match whose text is not a valid JSON string. .some(path): the cwd.
    private static func cwdInHead(of url: URL) -> String?? {
        let head = String(decoding: InventoryFileIO.readData(url, maxBytes: projectHeadBytes) ?? Data(), as: UTF8.self)
        guard let match = cwdPattern.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
              let range = Range(match.range(at: 1), in: head) else { return nil }
        return .some((try? OrderedJSON(text: "\"\(head[range])\""))?.root.stringValue)
    }

    private static func codexProjectKeys(_ configFile: URL) -> [String] {
        guard let data = InventoryFileIO.readData(configFile, maxBytes: InventoryFileIO.maxTextBytes) else { return [] }
        let doc = TOMLReader.read(String(decoding: data, as: UTF8.self))
        return doc.tablePaths(under: ["projects"]).compactMap { $0.count >= 2 ? $0[1] : nil }
    }
}
