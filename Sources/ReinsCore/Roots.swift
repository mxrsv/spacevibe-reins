import Foundation

/// The folders of one CLI that Reins reads.
public struct CLIRoots: Equatable, Sendable {
    public let root: URL
    public let skills: URL
    public let agents: URL
    /// Claude Code: `settings.json`. Codex: `hooks.json`.
    public let hookFile: URL
    /// Session logs: Claude `projects/`, Codex `sessions/`.
    public let logs: URL
}

public enum RootsError: Error, Equatable, Sendable {
    /// REINS_TEST=1 and a root sits under the real home. `label` is claude, codex or reins; `path` is the offending root.
    case underRealHome(label: String, path: String)
}

extension RootsError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .underRealHome(let label, let path):
            return "REINS_TEST=1: the \(label) root \(path) is under the real home. Point HOME, CLAUDE_CONFIG_DIR, CODEX_HOME and REINS_HOME at a temporary folder."
        }
    }
}

/// Where the config, the logs and Reins' own data live (AC3). Same rules as `roots()` in core/inventory.mjs.
public struct Roots: Equatable, Sendable {
    public let claude: CLIRoots
    public let codex: CLIRoots
    /// Reins' own data: journal, trash, caches.
    public let data: URL

    /// - Parameters:
    ///   - env: HOME, CLAUDE_CONFIG_DIR, CODEX_HOME, REINS_HOME and REINS_TEST. An empty value counts as unset.
    ///   - realHome: the account's real home folder, from the password database. Tests pass a stand-in.
    /// - Throws: `RootsError.underRealHome` when REINS_TEST is "1" and a root, or the real path behind it, is under the real home.
    public static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        realHome: String = Roots.realHomeDirectory()
    ) throws -> Roots {
        func value(_ key: String) -> String? { env[key].flatMap { $0.isEmpty ? nil : $0 } }
        let home = value("HOME") ?? realHome
        let claudeRoot = value("CLAUDE_CONFIG_DIR") ?? (home as NSString).appendingPathComponent(".claude")
        let codexRoot = value("CODEX_HOME") ?? (home as NSString).appendingPathComponent(".codex")
        let dataRoot = value("REINS_HOME") ?? (home as NSString).appendingPathComponent(".reins")
        if env["REINS_TEST"] == "1" {
            try assertNotUnderRealHome(realHome: realHome, roots: [("claude", claudeRoot), ("codex", codexRoot), ("reins", dataRoot)])
        }
        func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }
        func cli(_ root: String, hookFile: String, logs: String) -> CLIRoots {
            let base = folder(root)
            return CLIRoots(
                root: base,
                skills: base.appendingPathComponent("skills", isDirectory: true),
                agents: base.appendingPathComponent("agents", isDirectory: true),
                hookFile: base.appendingPathComponent(hookFile),
                logs: base.appendingPathComponent(logs, isDirectory: true)
            )
        }
        return Roots(
            claude: cli(claudeRoot, hookFile: "settings.json", logs: "projects"),
            codex: cli(codexRoot, hookFile: "hooks.json", logs: "sessions"),
            data: folder(dataRoot)
        )
    }

    /// The home folder from the password database, not from $HOME, so a test that overrides HOME cannot hide it.
    public static func realHomeDirectory() -> String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    private static func assertNotUnderRealHome(realHome: String, roots: [(String, String)]) throws {
        let homes = Set([standardized(realHome), resolvedPath(realHome)])
        for (label, path) in roots {
            let candidates = [standardized(path), resolvedPath(path)]
            if candidates.contains(where: { candidate in homes.contains(where: { isUnder(candidate, $0) }) }) {
                throw RootsError.underRealHome(label: label, path: path)
            }
        }
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// The real path with every symlink followed. For a path that does not exist yet, the deepest existing
    /// ancestor is resolved and the rest appended, so a symlinked parent cannot hide a missing leaf.
    static func resolvedPath(_ path: String) -> String {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        var tail: [String] = []
        while true {
            if let resolved = realpath(url.path, nil) {
                defer { free(resolved) }
                return (tail.reversed()).reduce(String(cString: resolved)) { ($0 as NSString).appendingPathComponent($1) }
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return standardized(path) }
            tail.append(url.lastPathComponent)
            url = parent
        }
    }

    private static func isUnder(_ path: String, _ directory: String) -> Bool {
        path == directory || path.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
    }
}
