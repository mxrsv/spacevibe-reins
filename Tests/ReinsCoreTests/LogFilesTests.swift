import Foundation
import Testing
@testable import ReinsCore

@Suite("LogFiles")
struct LogFilesTests {
    @Test("naming: which names are logs, and the shared base name of both forms")
    func naming() {
        #expect(LogFiles.isLog("a.jsonl"))
        #expect(LogFiles.isLog("a.jsonl.zst"))
        #expect(LogFiles.isLog("a.jsonl.zstd"))
        #expect(!LogFiles.isLog("a.json"))
        #expect(!LogFiles.isLog("a.zst"))
        #expect(!LogFiles.isLog("a.jsonl.bak"))
        #expect(!LogFiles.isLog("a.jsonl.zst.tmp"))
        let plain = URL(fileURLWithPath: "/x/rollout-1.jsonl")
        let packed = URL(fileURLWithPath: "/x/rollout-1.jsonl.zst")
        #expect(LogFiles.baseName(plain) == "rollout-1")
        #expect(LogFiles.baseName(packed) == "rollout-1")
        #expect(LogFiles.isCompressed(packed))
        #expect(LogFiles.isCompressed(URL(fileURLWithPath: "/x/a.jsonl.zstd")))
        #expect(!LogFiles.isCompressed(plain))
    }

    @Test("walk finds both forms, lists only the plain one when both exist, ignores symlinks and other files")
    func walk() throws {
        let home = try TempHome()
        try home.write("logs/a.jsonl", "{}\n")
        try home.write("logs/a.jsonl.zst", Fixtures.data("zst/small.jsonl.zst"))
        try home.write("logs/b.jsonl.zst", Fixtures.data("zst/small.jsonl.zst"))
        try home.write("logs/2026/11/c.jsonl", "{}\n")
        try home.write("logs/notes.txt", "x")
        try home.write("logs/d.json", "{}")
        try home.write("logs/.hidden.jsonl", "{}\n")
        try home.write("elsewhere/e.jsonl", "{}\n")
        try FileManager.default.createSymbolicLink(at: home.url("logs/link.jsonl"), withDestinationURL: home.url("elsewhere/e.jsonl"))
        try FileManager.default.createSymbolicLink(at: home.url("logs/linkdir"), withDestinationURL: home.url("elsewhere"))

        let found = LogFiles.walk(home.url("logs")).map { $0.path.replacingOccurrences(of: home.url("logs").path + "/", with: "") }
        #expect(found == [".hidden.jsonl", "2026/11/c.jsonl", "a.jsonl", "b.jsonl.zst"])
        #expect(LogFiles.walk(home.url("missing")).isEmpty)
    }

    @Test("forEachLine reads plain and compressed logs the same, including a last line without a newline")
    func lines() throws {
        let home = try TempHome()
        let plain = try home.write("p.jsonl", "{\"a\":1}\n\n{\"b\":\"é\"}\n{\"c\":3}")
        var seen: [String] = []
        try LogFiles.forEachLine(at: plain) { seen.append(String(decoding: $0, as: UTF8.self)) }
        #expect(seen == ["{\"a\":1}", "", "{\"b\":\"é\"}", "{\"c\":3}"])

        let small = try String(contentsOf: Fixtures.url("zst/small.jsonl"), encoding: .utf8)
        var fromZst: [String] = []
        try LogFiles.forEachLine(at: Fixtures.url("zst/small.jsonl.zst")) { fromZst.append(String(decoding: $0, as: UTF8.self)) }
        #expect(fromZst == small.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init))
    }

    @Test("forEachLine on the 5.5 MB compressed log yields every line once, intact across chunk boundaries")
    func largeLines() throws {
        let meta = try #require(try Fixtures.json("zst/large.meta.json") as? [String: Any])
        var count = 0
        var broken = 0
        try LogFiles.forEachLine(at: Fixtures.url("zst/large.jsonl.zst")) { line in
            count += 1
            if line.first != UInt8(ascii: "{") || line.last != UInt8(ascii: "}") { broken += 1 }
        }
        #expect(count == meta["lines"] as? Int)
        #expect(broken == 0)
    }

    @Test("a line over the cap is skipped and counted; the lines around it survive")
    func lineCap() throws {
        let home = try TempHome()
        let big = "{\"x\":\"" + String(repeating: "y", count: 5_000) + "\"}"
        let file = try home.write("c.jsonl", "{\"a\":1}\n\(big)\n{\"b\":2}\n\(big)")
        var seen: [String] = []
        let skipped = try LogFiles.forEachLine(at: file, maxLineBytes: 1_000) { seen.append(String(decoding: $0, as: UTF8.self)) }
        #expect(seen == ["{\"a\":1}", "{\"b\":2}"])
        #expect(skipped == 2)
    }

    @Test("the reader factory picks the class from the extension")
    func factory() {
        #expect(LogFiles.reader(for: URL(fileURLWithPath: "/x/a.jsonl")) is TailReader)
        #expect(LogFiles.reader(for: URL(fileURLWithPath: "/x/a.jsonl.zst")) is CompressedLogReader)
    }
}
