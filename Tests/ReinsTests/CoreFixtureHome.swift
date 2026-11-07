import Foundation
import Testing
import ReinsCore
@testable import Reins

/// A private copy of the synthetic fixture home (`core/testdata/fixtures`) and the environment that points both engines at
/// it (S-R1: never the real home), for the tests that run the Swift engine and the real Go core side by side.
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
            .appendingPathComponent("reins-core-client-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        let fm = FileManager.default
        for (relative, mtime) in mtimes {
            let text = try String(contentsOf: source.appendingPathComponent("home/\(relative)"), encoding: .utf8)
            let target = home.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.replacingOccurrences(of: token, with: home.path).utf8).write(to: target)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: mtime / 1000)], ofItemAtPath: target.path)
        }
        var fixture = [
            "HOME": home.path, "CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path,
            "CODEX_HOME": home.appendingPathComponent(".codex").path, "SPACEVIBE_HOME": home.appendingPathComponent(".spacevibe").path,
            "SPACEVIBE_TEST": "1",
        ]
        fixture.merge(extraEnvironment) { _, new in new }
        environment = ProcessInfo.processInfo.environment.merging(fixture) { _, new in new }
    }

    func remove() { try? FileManager.default.removeItem(at: home) }

    /// The Swift engine on the same folders the core gets.
    func roots() throws -> Roots { try Roots.resolve(env: environment) }

    /// The Go core `scripts/test.sh` builds. A bare `swift test` has none: run `scripts/test.sh`.
    static func coreBinary() throws -> URL {
        let path = try #require(ProcessInfo.processInfo.environment[CoreEnvironment.binaryOverride], "run scripts/test.sh: it builds the core and exports SPACEVIBE_CORE_BINARY")
        return URL(fileURLWithPath: path)
    }

    func client() throws -> CoreClient { CoreClient(binary: try Self.coreBinary(), environment: environment) }

    /// Every file under the home except Reins' own data folder: path relative to the home, and its bytes.
    func tree() throws -> [String: Data] {
        var out: [String: Data] = [:]
        for relative in try FileManager.default.subpathsOfDirectory(atPath: home.path) where relative != ".spacevibe" && !relative.hasPrefix(".spacevibe/") {
            let url = home.appendingPathComponent(relative)
            if (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true { out[relative] = try Data(contentsOf: url) }
        }
        return out
    }
}
