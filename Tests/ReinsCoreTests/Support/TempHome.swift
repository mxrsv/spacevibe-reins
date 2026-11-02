import Foundation

/// A throwaway HOME. Every test that touches files builds one; nothing reads the real ~/.claude or ~/.codex.
final class TempHome {
    /// Real path (symlinks resolved), so path comparisons and hashes are stable.
    let root: URL

    init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let made = base.appendingPathComponent("reins-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: realpathString(made.path), isDirectory: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var claude: URL { root.appendingPathComponent(".claude", isDirectory: true) }
    var codex: URL { root.appendingPathComponent(".codex", isDirectory: true) }
    var reins: URL { root.appendingPathComponent(".reins", isDirectory: true) }

    /// Environment that points every root at this folder, with the real-home guard on.
    var env: [String: String] {
        [
            "HOME": root.path,
            "CLAUDE_CONFIG_DIR": claude.path,
            "CODEX_HOME": codex.path,
            "REINS_HOME": reins.path,
            "REINS_TEST": "1",
        ]
    }

    func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    @discardableResult
    func write(_ relative: String, _ text: String) throws -> URL {
        try write(relative, Data(text.utf8))
    }

    @discardableResult
    func write(_ relative: String, _ data: Data) throws -> URL {
        let target = url(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target)
        return target
    }
}

func realpathString(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}
