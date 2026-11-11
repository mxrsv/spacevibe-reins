import Foundation
import Testing
@testable import SpaceVibe

/// A private copy of the synthetic fixture home (`core/testdata/fixtures`) and the environment that points the real Go
/// core at it (S-R1: never the real home). The tree is materialized here from `fixtures/manifest.json`, so it depends on no engine.
struct CoreFixtureHome {
    let home: URL
    /// Full environment for a core process: ours plus the fixture's folders and `SPACEVIBE_TEST=1`.
    let environment: [String: String]

    var data: URL { home.appendingPathComponent(".spacevibe", isDirectory: true) }

    init(extraEnvironment: [String: String] = [:]) throws {
        let source = CoreTestData.directory.appendingPathComponent("fixtures", isDirectory: true)
        let manifest = try #require(try CoreTestData.json("fixtures/manifest.json") as? [String: Any])
        let token = try #require(manifest["token"] as? String)
        let mtimes = try #require(manifest["mtimes"] as? [String: Double])
        home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("spacevibe-core-client-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        let fm = FileManager.default
        let shift = Self.mtimeShift()
        for (relative, mtime) in mtimes {
            let text = try String(contentsOf: source.appendingPathComponent("home/\(relative)"), encoding: .utf8)
            let target = home.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.replacingOccurrences(of: token, with: home.path).utf8).write(to: target)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: mtime / 1000 + shift)], ofItemAtPath: target.path)
        }
        var fixture = [
            "HOME": home.path, "CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path,
            "CODEX_HOME": home.appendingPathComponent(".codex").path, "SPACEVIBE_HOME": home.appendingPathComponent(".spacevibe").path,
            "SPACEVIBE_TEST": "1",
        ]
        fixture.merge(extraEnvironment) { _, new in new }
        environment = ProcessInfo.processInfo.environment.merging(fixture) { _, new in new }
    }

    /// The fixture's modification times are fixed (late October to 2026-11-02), and the core reads only the last 14 days of
    /// session logs, so on a fixed clock this copy would lose its sessions, failures and files day by day. The copy keeps the
    /// distance the times had to now on `mtimeAnchor`, the day the suites were last checked against it, by moving every time
    /// forward by the days since; never backward, and never more than that.
    static let mtimeAnchor = Date(timeIntervalSince1970: 1_794_268_800) // 2026-11-10T00:00:00Z

    static func mtimeShift(now: Date = Date()) -> TimeInterval { max(0, now.timeIntervalSince(mtimeAnchor)) }

    /// The way a test builds one. The copy is synchronous file work (about 0.2 s under load); done on the main actor it holds up every
    /// other `@MainActor` suite, and the Loadout model suite waits at most 10 s for its rows. So it runs off the main actor.
    static func make(extraEnvironment: [String: String] = [:]) async throws -> CoreFixtureHome {
        try await Task.detached { try CoreFixtureHome(extraEnvironment: extraEnvironment) }.value
    }

    func remove() { try? FileManager.default.removeItem(at: home) }

    /// The Go core `scripts/test.sh` builds. A bare `swift test` has none: run `scripts/test.sh`.
    static func coreBinary() throws -> URL {
        let path = try #require(ProcessInfo.processInfo.environment[CoreEnvironment.binaryOverride], "run scripts/test.sh: it builds the core and exports SPACEVIBE_CORE_BINARY")
        return URL(fileURLWithPath: path)
    }

    func client() throws -> CoreClient { CoreClient(binary: try Self.coreBinary(), environment: environment) }

    /// Every file under the home except SpaceVibe's own data folder: path relative to the home, and its bytes. Read off the main actor,
    /// for the reason `make` gives.
    func tree() async throws -> [String: Data] {
        try await Task.detached { try self.readTree() }.value
    }

    private func readTree() throws -> [String: Data] {
        var out: [String: Data] = [:]
        for relative in try FileManager.default.subpathsOfDirectory(atPath: home.path) where relative != ".spacevibe" && !relative.hasPrefix(".spacevibe/") {
            let url = home.appendingPathComponent(relative)
            if (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true { out[relative] = try Data(contentsOf: url) }
        }
        return out
    }
}

extension Dictionary where Key == String, Value == Data {
    /// The paths whose bytes differ, or that exist on only one side (compares two `CoreFixtureHome.tree()` snapshots).
    func difference(from other: [String: Data]) -> [String] {
        Set(keys).union(other.keys).filter { self[$0] != other[$0] }.sorted()
    }
}
