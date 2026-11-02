import Foundation
import Testing
@testable import ReinsCore

@Suite("TailReader")
struct TailReaderTests {
    private func lines(_ reader: some LogReader) throws -> (lines: [String], result: LogReadResult, resets: Int) {
        var out: [String] = []
        var resets = 0
        let result = try reader.read({ out.append(String(decoding: $0, as: UTF8.self)) }, onReset: { resets += 1 })
        return (out, result, resets)
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    @Test("a second read returns only what was appended; a half-written line waits for its newline")
    func incremental() throws {
        let home = try TempHome()
        let file = try home.write("s.jsonl", "{\"n\":1}\n{\"n\":2}\n{\"n\":")
        let reader = TailReader(url: file)
        let first = try lines(reader)
        #expect(first.lines == ["{\"n\":1}", "{\"n\":2}"])
        #expect(first.result.lines == 2)
        #expect(first.result.size == 21)

        #expect(try lines(reader).lines.isEmpty)

        try append("3}\n{\"n\":4}\n", to: file)
        let second = try lines(reader)
        #expect(second.lines == ["{\"n\":3}", "{\"n\":4}"])
        #expect(second.resets == 0)
        #expect(reader.offset == (try Data(contentsOf: file)).count)
    }

    @Test("a file that shrank is read again from the start, with onReset")
    func truncation() throws {
        let home = try TempHome()
        let file = try home.write("t.jsonl", "{\"a\":1}\n{\"a\":2}\n{\"a\":3}\n")
        let reader = TailReader(url: file)
        _ = try lines(reader)
        try Data("{\"b\":1}\n".utf8).write(to: file)
        let again = try lines(reader)
        #expect(again.lines == ["{\"b\":1}"])
        #expect(again.resets == 1)
        #expect(again.result.didReset)
    }

    @Test("a file replaced by another (new inode), even a longer one, is read again from the start")
    func replacedInode() throws {
        let home = try TempHome()
        let file = try home.write("r.jsonl", "{\"a\":1}\n")
        let reader = TailReader(url: file)
        #expect(try lines(reader).lines == ["{\"a\":1}"])
        let replacement = try home.write("r-new.jsonl", "{\"z\":9}\n{\"z\":8}\n{\"z\":7}\n")
        _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)
        let again = try lines(reader)
        #expect(again.resets == 1)
        #expect(again.lines == ["{\"z\":9}", "{\"z\":8}", "{\"z\":7}"])
    }

    @Test("a missing file reports missing, then reads once it appears")
    func missing() throws {
        let home = try TempHome()
        let reader = TailReader(url: home.url("later.jsonl"))
        let none = try lines(reader)
        #expect(none.result.missing)
        #expect(none.lines.isEmpty)
        try home.write("later.jsonl", "{\"a\":1}\n")
        #expect(try lines(reader).lines == ["{\"a\":1}"])
    }

    @Test("maxBytes starts late and drops the cut line")
    func maxBytes() throws {
        let home = try TempHome()
        let body = (1...50).map { "{\"n\":\($0)}" }.joined(separator: "\n") + "\n"
        let file = try home.write("m.jsonl", body)
        let reader = TailReader(url: file, maxBytes: 40)
        let read = try lines(reader)
        #expect(read.result.truncated)
        #expect(read.lines.last == "{\"n\":50}")
        #expect(read.lines.count >= 3 && read.lines.count <= 5)
        #expect(!read.lines.contains("{\"n\":1}"))
        // every line passed is whole
        #expect(read.lines.allSatisfy { $0.hasPrefix("{") && $0.hasSuffix("}") })
    }

    @Test("an over-long line is skipped and counted, and the next lines still arrive")
    func lineCap() throws {
        let home = try TempHome()
        let big = "{\"x\":\"" + String(repeating: "y", count: 3_000) + "\"}"
        let file = try home.write("c.jsonl", "{\"a\":1}\n\(big)\n{\"b\":2}\n")
        let reader = TailReader(url: file, maxLineBytes: 500)
        let read = try lines(reader)
        #expect(read.lines == ["{\"a\":1}", "{\"b\":2}"])
        #expect(read.result.oversizedLines == 1)
        #expect(reader.oversizedLines == 1)
    }

    @Test("a line that grows past the cap across reads is dropped once, whole")
    func capAcrossReads() throws {
        let home = try TempHome()
        let file = try home.write("g.jsonl", "{\"a\":1}\n{\"x\":\"" + String(repeating: "y", count: 2_000))
        let reader = TailReader(url: file, maxLineBytes: 500)
        _ = try lines(reader)
        try append(String(repeating: "z", count: 100) + "\"}\n{\"b\":2}\n", to: file)
        let next = try lines(reader)
        #expect(next.lines == ["{\"b\":2}"])
        #expect(reader.oversizedLines == 1)
    }

    @Test("lines that are not objects are counted, blank lines are not")
    func invalidLines() throws {
        let home = try TempHome()
        let file = try home.write("i.jsonl", "{\"a\":1}\nnot json at all\n\n   \n[1,2]\n{\"b\":2}\n\"str\"\n")
        let reader = TailReader(url: file)
        let read = try lines(reader)
        #expect(read.lines == ["{\"a\":1}", "{\"b\":2}"])
        #expect(read.result.invalidLines == 3)
        #expect(reader.invalidLines == 3)
        reader.noteInvalidLine()
        #expect(reader.invalidLines == 4)
        // a second read with nothing new adds nothing
        #expect(try lines(reader).result.invalidLines == 0)
    }

    @Test("with the shape check off, any non-blank line passes")
    func shapeCheckOff() throws {
        let home = try TempHome()
        let file = try home.write("o.jsonl", "plain text\n\n[1]\n")
        #expect(try lines(TailReader(url: file, requireObjectShape: false)).lines == ["plain text", "[1]"])
    }

    @Test("multi-byte characters survive chunk boundaries")
    func multibyte() throws {
        let home = try TempHome()
        let row = "{\"t\":\"" + String(repeating: "é🙂", count: 60_000) + "\"}"
        let file = try home.write("u.jsonl", [row, row, row].joined(separator: "\n") + "\n")
        let read = try lines(TailReader(url: file))
        #expect(read.lines == [row, row, row])
    }

    @Test("an unreadable file throws an error that carries only errno")
    func unreadable() throws {
        let home = try TempHome()
        let file = try home.write("p.jsonl", "{\"a\":1}\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        #expect(throws: LogReadError.self) { _ = try TailReader(url: file).read({ _ in }) }
    }
}

@Suite("CompressedLogReader")
struct CompressedLogReaderTests {
    @Test("reads a .zst log once, then nothing until the file changes")
    func readsOnce() throws {
        let home = try TempHome()
        let file = try home.write("a.jsonl.zst", Fixtures.data("zst/small.jsonl.zst"))
        let reader = CompressedLogReader(url: file)
        var seen: [Data] = []
        let first = try reader.read({ seen.append($0) })
        #expect(seen.count == 3)
        #expect(first.lines == 3)
        var again = 0
        let second = try reader.read({ _ in again += 1 })
        #expect(again == 0)
        #expect(!second.didReset)

        try Fixtures.data("zst/twice.jsonl.zst").write(to: file)
        var resets = 0
        var after = 0
        let third = try reader.read({ _ in after += 1 }, onReset: { resets += 1 })
        #expect(resets == 1 && third.didReset)
        #expect(after == 6)
    }

    @Test("maxBytes keeps the last lines of the log")
    func tail() throws {
        let reader = CompressedLogReader(url: Fixtures.url("zst/large.jsonl.zst"), maxBytes: 4_000)
        var seen: [Data] = []
        let result = try reader.read({ seen.append($0) })
        #expect(result.truncated)
        #expect(seen.count > 5 && seen.count < 80)
        let lastData = try #require(seen.last)
        let last = String(decoding: lastData, as: UTF8.self)
        let meta = try #require(try Fixtures.json("zst/large.meta.json") as? [String: Any])
        #expect(last.hasPrefix("{\"i\":\((meta["lines"] as! Int) - 1),"))
    }

    @Test("a truncated archive surfaces ZstdError.truncated and a missing one reports missing")
    func errors() throws {
        let home = try TempHome()
        let full = try Fixtures.data("zst/cli-made.jsonl.zst")
        let cut = try home.write("cut.jsonl.zst", full.prefix(full.count / 2))
        #expect(throws: ZstdError.truncated) { _ = try CompressedLogReader(url: cut).read({ _ in }) }
        #expect(try CompressedLogReader(url: home.url("none.jsonl.zst")).read({ _ in }).missing)
    }
}
