import Foundation

/// The synthetic HOME stored under Fixtures/home, and its golden JSON (frozen goldens (SV5), last generated at b58269d3f3eb).
///
/// Why a fixed path: ids in the goldens (hook ids, project ids) are hashes of absolute paths. The Node side runs on
/// `canonicalRoot`, so Swift reads the same tree at the same path and the ids agree. The tree there is READ-ONLY and shared
/// by all tests. A test that writes uses `materialize(into:)` on a folder of its own (its path-hashed ids will differ from the
/// goldens, which is fine for write tests).
enum FixtureHome {
    static let token = "$HOME"
    /// The path the frozen goldens (SV5), last generated at b58269d3f3eb, ran on; ids in the goldens hash it.
    static let canonicalRoot = URL(fileURLWithPath: "/private/tmp/reins-fixture-home", isDirectory: true)
    private static let stampName = ".fixture-stamp"
    private static let lock = NSLock()

    struct Manifest: Decodable {
        let now: Double
        let token: String
        let digest: String
        let mtimes: [String: Double]
    }

    static func manifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Fixtures.data("manifest.json"))
    }

    /// The fixed "now" of the fixture (ms since 1970); pass it wherever the Node run used it.
    static func now() throws -> Date { Date(timeIntervalSince1970: try manifest().now / 1000) }

    /// Environment pointing every root at the shared tree, with the real-home guard on.
    static var env: [String: String] {
        let root = canonicalRoot.path
        return [
            "HOME": root, "CLAUDE_CONFIG_DIR": root + "/.claude", "CODEX_HOME": root + "/.codex",
            "REINS_HOME": root + "/.reins", "REINS_TEST": "1",
        ]
    }

    /// The shared read-only tree at `canonicalRoot`, built once and reused while the manifest digest is unchanged.
    @discardableResult
    static func materialize() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        let manifest = try manifest()
        let fm = FileManager.default
        if stampMatches(canonicalRoot, manifest.digest) { return canonicalRoot }

        let parent = canonicalRoot.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("reins-fixture-home-\(UUID().uuidString)", isDirectory: true)
        try build(into: staging, substituting: canonicalRoot.path, manifest: manifest)
        if fm.fileExists(atPath: canonicalRoot.path) {
            // Only ever removes the canonical fixture folder, and never through a symlink.
            let attributes = try fm.attributesOfItem(atPath: canonicalRoot.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw FixtureError.notAFolder }
            try fm.removeItem(at: canonicalRoot)
        }
        do {
            try fm.moveItem(at: staging, to: canonicalRoot)
        } catch {
            try? fm.removeItem(at: staging)
            // Another test process won the race; its tree is the same bytes.
            guard stampMatches(canonicalRoot, manifest.digest) else { throw error }
        }
        return canonicalRoot
    }

    /// A private copy at `destination` (which must not exist), with `$HOME` replaced by its own path.
    static func materialize(into destination: URL) throws {
        try build(into: destination, substituting: destination.path, manifest: manifest())
    }

    enum FixtureError: Error { case notAFolder }

    private static func stampMatches(_ root: URL, _ digest: String) -> Bool {
        (try? String(contentsOf: root.appendingPathComponent(stampName), encoding: .utf8)) == digest
    }

    private static func build(into destination: URL, substituting rootPath: String, manifest: Manifest) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = Fixtures.url("home")
        for (relative, mtime) in manifest.mtimes {
            let text = try String(contentsOf: source.appendingPathComponent(relative), encoding: .utf8)
            let target = destination.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.replacingOccurrences(of: manifest.token, with: rootPath).utf8).write(to: target)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: mtime / 1000)], ofItemAtPath: target.path)
        }
        try fm.createDirectory(at: destination.appendingPathComponent(".reins"), withIntermediateDirectories: true)
        try Data(manifest.digest.utf8).write(to: destination.appendingPathComponent(stampName))
    }

    // MARK: Goldens

    /// A golden file parsed with Foundation (dictionary key order is irrelevant to comparisons).
    static func golden(_ name: String) throws -> Any {
        try Fixtures.json("golden/\(name).json")
    }

    /// Replaces the fixture root path with `$HOME` in every string of a JSON value, as the goldens were written.
    /// Apply it to a Swift result before comparing with a golden.
    static func normalize(_ value: Any, root: URL = canonicalRoot) -> Any {
        switch value {
        case let text as String: return text.replacingOccurrences(of: root.path, with: token)
        case let array as [Any]: return array.map { normalize($0, root: root) }
        case let dictionary as [String: Any]: return dictionary.mapValues { normalize($0, root: root) }
        default: return value
        }
    }

    /// The path of the first difference between two JSON values (`$.items[3].cells.claude.state`), or nil when equal.
    /// Arrays compare in order; sort both sides by id first when order is not part of the contract.
    static func firstDifference(_ actual: Any, _ expected: Any, path: String = "$") -> String? {
        switch (actual, expected) {
        case let (a as [String: Any], e as [String: Any]):
            for key in Set(a.keys).union(e.keys).sorted() {
                guard let av = a[key], let ev = e[key] else { return "\(path).\(key) (present on one side only)" }
                if let diff = firstDifference(av, ev, path: "\(path).\(key)") { return diff }
            }
            return nil
        case let (a as [Any], e as [Any]):
            if a.count != e.count { return "\(path) (count \(a.count) vs \(e.count))" }
            for (index, pair) in zip(a, e).enumerated() {
                if let diff = firstDifference(pair.0, pair.1, path: "\(path)[\(index)]") { return diff }
            }
            return nil
        case let (a as NSNumber, e as NSNumber):
            return a == e ? nil : "\(path) (\(a) vs \(e))"
        case let (a as String, e as String):
            return a == e ? nil : "\(path) (\"\(a)\" vs \"\(e)\")"
        case (is NSNull, is NSNull):
            return nil
        default:
            return "\(path) (different kinds)"
        }
    }
}
