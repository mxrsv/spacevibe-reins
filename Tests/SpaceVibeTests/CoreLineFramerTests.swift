import Foundation
import Testing
@testable import SpaceVibe

@Suite("CoreLineFramer")
struct CoreLineFramerTests {
    private func feed(_ framer: inout CoreLineFramer, _ text: String) throws -> [String] {
        let bytes = Array(text.utf8)
        return try framer.feed(bytes, count: bytes.count).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test("lines split across chunks come out whole, and blank lines are dropped")
    func splitsAcrossChunks() throws {
        var framer = CoreLineFramer()
        #expect(try feed(&framer, "{\"a\":1}\n{\"b\"") == ["{\"a\":1}"])
        #expect(try feed(&framer, ":2}\n\n\n{\"c\":3}\n") == ["{\"b\":2}", "{\"c\":3}"])
        #expect(framer.bufferedCount == 0)
    }

    @Test("a 20 MiB line fed in 64 KiB reads is one line, found without searching the bytes again")
    func largeLine() throws {
        var framer = CoreLineFramer()
        let chunk = [UInt8](repeating: 0x61, count: 64 * 1024)
        var lines: [Data] = []
        let started = ContinuousClock.now
        for _ in 0 ..< 320 { lines += try framer.feed(chunk, count: chunk.count) }
        #expect(lines.isEmpty)
        let tail = Array("end\n".utf8)
        lines += try framer.feed(tail, count: tail.count)
        let took = ContinuousClock.now - started
        #expect(lines.count == 1 && lines[0].count == 320 * 64 * 1024 + 3)
        #expect(took < .seconds(2), "framing took \(took)")
    }

    @Test("a line past the cap throws before the buffer passes the cap, and the buffer is empty after")
    func overCap() throws {
        var framer = CoreLineFramer()
        let chunk = [UInt8](repeating: 0x61, count: 64 * 1024)
        var fed = 0
        var failed = false
        while fed <= CoreLineFramer.maxLine + chunk.count {
            do { _ = try framer.feed(chunk, count: chunk.count) } catch is CoreLineFramer.Overflow {
                failed = true
                break
            }
            fed += chunk.count
            #expect(framer.bufferedCount <= CoreLineFramer.maxLine)
        }
        #expect(failed)
        #expect(fed <= CoreLineFramer.maxLine)
        #expect(framer.bufferedCount == 0)
    }

    @Test("a line exactly at the cap is accepted")
    func atCap() throws {
        var framer = CoreLineFramer()
        let line = [UInt8](repeating: 0x61, count: CoreLineFramer.maxLine) + [0x0A]
        let lines = try framer.feed(line, count: line.count)
        #expect(lines.count == 1 && lines[0].count == CoreLineFramer.maxLine)
    }
}
