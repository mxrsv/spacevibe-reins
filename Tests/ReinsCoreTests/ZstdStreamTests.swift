import Foundation
import Testing
@testable import ReinsCore

@Suite("ZstdStream")
struct ZstdStreamTests {
    private func read(_ relative: String) throws -> Data {
        try ZstdStream.readAll(url: Fixtures.url(relative))
    }

    @Test("reads a file written by zlib.zstdCompressSync byte for byte")
    func smallFromNode() throws {
        #expect(try read("zst/small.jsonl.zst") == Fixtures.data("zst/small.jsonl"))
    }

    @Test("reads a file written by the zstd command line tool (level 19)")
    func smallFromCLI() throws {
        let plain = try Fixtures.data("zst/cli-made.jsonl")
        #expect(plain.count > 30_000)
        #expect(try read("zst/cli-made.jsonl.zst") == plain)
    }

    @Test("concatenated frames read as one stream")
    func concatenatedFrames() throws {
        let small = try Fixtures.data("zst/small.jsonl")
        #expect(try read("zst/twice.jsonl.zst") == small + small)
    }

    @Test("a 5.5 MB stream decodes to identical bytes, in several chunks")
    func large() throws {
        let meta = try #require(try Fixtures.json("zst/large.meta.json") as? [String: Any])
        let stream = try ZstdStream(url: Fixtures.url("zst/large.jsonl.zst"))
        var all = Data()
        var chunks = 0
        try stream.forEachChunk { all.append($0); chunks += 1 }
        #expect(all.count == meta["bytes"] as? Int)
        #expect(sha256Hex(all) == meta["sha256"] as? String)
        #expect(all.count > 5_000_000)
        #expect(chunks > 10)
        #expect(all.reduce(into: 0) { $0 += $1 == 0x0A ? 1 : 0 } == meta["lines"] as? Int)
    }

    @Test("a file cut inside a frame is reported as truncated")
    func truncated() throws {
        let home = try TempHome()
        let full = try Fixtures.data("zst/cli-made.jsonl.zst")
        let cut = try home.write("cut.zst", full.prefix(full.count / 2))
        #expect(throws: ZstdError.truncated) { try ZstdStream.readAll(url: cut) }
    }

    @Test("garbage is reported as corrupt without quoting its content")
    func corrupt() throws {
        let home = try TempHome()
        let secret = "do-not-quote-this-text"
        let file = try home.write("bad.zst", secret + String(repeating: "x", count: 64))
        do {
            _ = try ZstdStream.readAll(url: file)
            Issue.record("expected an error")
        } catch let error as ZstdError {
            guard case .corrupt(let name) = error else { Issue.record("wrong error \(error)"); return }
            #expect(!name.contains(secret))
        }
    }

    @Test("a missing file is cannotOpen")
    func missing() {
        #expect(throws: ZstdError.cannotOpen) { _ = try ZstdStream(url: Fixtures.url("zst/none.zst")) }
    }
}
