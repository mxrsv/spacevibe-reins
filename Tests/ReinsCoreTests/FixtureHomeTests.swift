import Foundation
import Testing
@testable import ReinsCore

@Suite("Fixture home and goldens")
struct FixtureHomeTests {
    @Test("the manifest lists the tree, and every listed file is committed")
    func manifestMatchesTree() throws {
        let manifest = try FixtureHome.manifest()
        #expect(manifest.token == "$HOME")
        #expect(manifest.mtimes.count > 200)
        #expect(manifest.digest.count == 64)
        for relative in manifest.mtimes.keys {
            #expect(FileManager.default.fileExists(atPath: Fixtures.url("home/\(relative)").path), "\(relative)")
        }
    }

    @Test("the committed tree is synthetic: no real home path, user name or leftover temp path")
    func treeIsSynthetic() throws {
        let manifest = try FixtureHome.manifest()
        let forbidden = [NSHomeDirectory(), NSUserName(), "/var/folders", "/Users/"].filter { $0.count > 3 }
        for relative in manifest.mtimes.keys {
            let text = try String(contentsOf: Fixtures.url("home/\(relative)"), encoding: .utf8)
            for needle in forbidden {
                #expect(!text.contains(needle), "\(relative) contains \(needle)")
            }
        }
    }

    @Test("materialize builds the tree at the canonical path with paths and mtimes restored")
    func materializes() throws {
        let root = try FixtureHome.materialize()
        #expect(root.path == "/private/tmp/reins-fixture-home")
        let manifest = try FixtureHome.manifest()
        let settings = try String(contentsOf: root.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        #expect(settings.contains(root.path + "/.claude/scripts/guard-destructive.sh"))
        #expect(!settings.contains("$HOME"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".claude/scripts/guard-destructive.sh").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".reins").path))
        // mtimes: a backdated config file and a log.
        for relative in [".claude/skills/ponytail/SKILL.md", ".claude/projects/-work-spacevibe-bench/session-000.jsonl"] {
            let expected = try #require(manifest.mtimes[relative])
            let actual = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(relative).path)[.modificationDate] as? Date
            #expect(abs((actual?.timeIntervalSince1970 ?? 0) * 1000 - expected) < 1, "\(relative)")
        }
        // a second call reuses the tree
        #expect(try FixtureHome.materialize() == root)
    }

    @Test("a private copy substitutes its own path and leaves no token")
    func privateCopy() throws {
        let home = try TempHome()
        let copy = home.url("copy")
        try FixtureHome.materialize(into: copy)
        let settings = try String(contentsOf: copy.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        #expect(settings.contains(copy.path + "/.claude/scripts/notify-done.sh"))
        #expect(!settings.contains("$HOME"))
    }

    @Test("the fixture roots pass the real-home guard")
    func rootsAreTemp() throws {
        _ = try FixtureHome.materialize()
        let roots = try Roots.resolve(env: FixtureHome.env)
        #expect(roots.claude.root.path == "/private/tmp/reins-fixture-home/.claude")
    }

    @Test("inventory.json parses and describes the tree: items, hooks, usage input, filter counts")
    func inventoryGoldenShape() throws {
        let golden = try #require(try FixtureHome.golden("inventory") as? [String: Any])
        let inventory = try #require(golden["inventory"] as? [String: Any])
        let items = try #require(inventory["items"] as? [[String: Any]])
        let hooks = try #require(inventory["hooks"] as? [[String: Any]])
        #expect(items.count > 20)
        #expect(hooks.count == 9)
        #expect((golden["usageInput"] as? [String: Any])?["totals"] != nil)
        let counts = try #require(golden["filterCounts"] as? [String: Any])
        #expect(counts["dead"] as? Int == 2)
        #expect(golden["now"] as? Double == (try FixtureHome.manifest().now))
        // sorted by id so reruns do not diff
        let ids = items.compactMap { $0["id"] as? String }
        #expect(ids == ids.sorted())
    }

    @Test("every file the inventory golden names exists in the materialized tree, and no real path leaks")
    func goldenAgreesWithTree() throws {
        let root = try FixtureHome.materialize()
        let golden = try #require(try FixtureHome.golden("inventory") as? [String: Any])
        let inventory = try #require(golden["inventory"] as? [String: Any])
        let rows = (inventory["items"] as? [[String: Any]] ?? []) + (inventory["hooks"] as? [[String: Any]] ?? [])
        var checked = 0
        for row in rows {
            let file = try #require(row["file"] as? String)
            #expect(file.hasPrefix("$HOME/"), "\(file)")
            let real = file.replacingOccurrences(of: "$HOME", with: root.path)
            #expect(FileManager.default.fileExists(atPath: real), "\(file)")
            checked += 1
        }
        #expect(checked > 30)
        let text = String(decoding: try Fixtures.data("golden/inventory.json"), as: UTF8.self)
        for needle in [NSHomeDirectory(), NSUserName(), "/var/folders", "/private/tmp", "/Users/"].filter({ $0.count > 3 }) {
            #expect(!text.contains(needle), "golden contains \(needle)")
        }
    }

    @Test("normalize and firstDifference behave as the later comparisons need")
    func helpers() {
        let actual: [String: Any] = ["p": "/private/tmp/reins-fixture-home/.claude", "n": [1, 2], "o": ["k": true]]
        let normalized = FixtureHome.normalize(actual) as? [String: Any]
        #expect(normalized?["p"] as? String == "$HOME/.claude")
        #expect(FixtureHome.firstDifference(normalized!, ["p": "$HOME/.claude", "n": [1, 2], "o": ["k": true]]) == nil)
        #expect(FixtureHome.firstDifference(normalized!, ["p": "$HOME/.claude", "n": [1, 3], "o": ["k": true]]) == "$.n[1] (2 vs 3)")
        #expect(FixtureHome.firstDifference(normalized!, ["p": "$HOME/.claude", "n": [1, 2]])?.hasPrefix("$.o") == true)
    }
}
