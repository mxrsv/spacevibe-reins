import Foundation
import Testing
@testable import ReinsCore

/// A zstd frame built by hand from raw and RLE blocks, so a test can make a tiny file that expands to hundreds of MB, or
/// a stream of many short lines, without a compressor. Block layout: RFC 8878 section 3.1.1.2.
private enum ZstdFrame {
    static let blockMax = 128 * 1024

    private static var header: [UInt8] {
        // Magic, then a descriptor with no checksum, dictionary or content size, then a 512 KB window.
        [0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x48]
    }

    private static func blockHeader(type: UInt32, size: Int, last: Bool) -> [UInt8] {
        let value = (last ? 1 : 0) | (type << 1) | (UInt32(size) << 3)
        return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF)]
    }

    /// `repeatCount` bytes of `byte`, as RLE blocks of 4 bytes each.
    static func repeated(_ byte: UInt8, count total: Int) -> Data {
        var out = header
        var left = total
        while left > 0 {
            let size = min(left, blockMax)
            left -= size
            out += blockHeader(type: 1, size: size, last: left == 0) + [byte]
        }
        return Data(out)
    }

    /// `content` stored as raw blocks.
    static func raw(_ content: Data) -> Data {
        var out = header
        var offset = content.startIndex
        repeat {
            let size = min(content.endIndex - offset, blockMax)
            let end = offset + size
            out += blockHeader(type: 0, size: size, last: end == content.endIndex)
            out += content[offset..<end]
            offset = end
        } while offset < content.endIndex
        return Data(out)
    }
}

private func chmod(_ mode: mode_t, _ url: URL) { _ = Foundation.chmod(url.path, mode) }

@Suite("Read-side hardening")
struct ReadHardeningTests {
    // MARK: Regular-file reads

    /// A regressed blocking reader must fail assertions instead of hanging the suite. Start with no writer;
    /// if the read has not returned, wait for its open, then supply EOF. Needing rescue is itself a failure.
    private func withFIFORescue<T>(_ fifo: URL, _ body: () throws -> T) throws -> T {
        let finished = DispatchSemaphore(value: 0)
        let rescued = DispatchSemaphore(value: 0)
        let rescue = DispatchGroup()
        rescue.enter()
        DispatchQueue.global().async {
            defer { rescue.leave() }
            guard finished.wait(timeout: .now() + .milliseconds(250)) == .timedOut else { return }
            while true {
                // ENXIO means the reader has not opened yet; retry so scheduler delays cannot strand it.
                let writer = open(fifo.path, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
                if writer >= 0 {
                    rescued.signal()
                    close(writer)
                    return
                }
                if finished.wait(timeout: .now() + .milliseconds(10)) == .success { return }
            }
        }
        defer {
            finished.signal()
            rescue.wait()
            #expect(rescued.wait(timeout: .now()) == .timedOut, "A regular-file reader must reject FIFO without a writer")
        }
        return try body()
    }

    @Test("inventory readers reject FIFOs and links to FIFOs without waiting for input", arguments: [false, true])
    func rejectFIFO(linked: Bool) throws {
        let home = try TempHome()
        let fifo = home.url("input")
        try #require(mkfifo(fifo.path, 0o600) == 0)
        let path = linked ? home.url("input-link") : fifo
        if linked { try FileManager.default.createSymbolicLink(at: path, withDestinationURL: fifo) }
        let data = try withFIFORescue(fifo) { InventoryFileIO.readData(path, maxBytes: 64) }
        #expect(data == nil)
        let json = try withFIFORescue(fifo) { InventoryFileIO.readJSON(path) }
        guard case .unreadable = json else { Issue.record("FIFO must be unreadable, not valid JSON or missing"); return }
    }

    @Test("a discovered project with FIFO settings reports unreadable and preserves other inventory")
    func discoveredProjectFIFO() throws {
        let home = try TempHome()
        let project = home.url("project")
        try home.write("project/.claude/skills/example/SKILL.md", "---\nname: example\n---\n")
        try home.write(".codex/config.toml", "[projects.\"\(project.path)\"]\ntrust_level = \"trusted\"\n")
        let fifo = project.appendingPathComponent(".claude/settings.json")
        try #require(mkfifo(fifo.path, 0o600) == 0)
        let roots = try Roots.resolve(env: home.env)
        let snapshot = try withFIFORescue(fifo) { Inventory.read(roots: roots) }
        #expect(snapshot.items.contains { $0.name == "example" && $0.project == project.path })
        #expect(snapshot.problems.contains { $0.contains(fifo.path) && $0.contains("cannot be read") })
    }

    @Test("regular files and symlinks retain byte limits and JSON classifications")
    func regularReadSemantics() throws {
        let home = try TempHome()
        let target = try home.write("input.json", "{\"value\":true}")
        let link = home.url("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        for path in [target, link] {
            #expect(InventoryFileIO.readData(path, maxBytes: 2) == Data("{\"".utf8))
            guard case .value(let json) = InventoryFileIO.readJSON(path) else { Issue.record("regular JSON must remain readable"); continue }
            #expect(json["value"]?.boolValue == true)
        }
        let missing = home.url("missing")
        guard case .missing = InventoryFileIO.readJSON(missing) else { Issue.record("absent file must remain missing"); return }
        guard case .unreadable = InventoryFileIO.readJSON(home.root) else { Issue.record("directory must be unreadable"); return }
        let invalid = try home.write("invalid.json", "{")
        guard case .invalid = InventoryFileIO.readJSON(invalid) else { Issue.record("malformed JSON must remain invalid"); return }
        let oversized = try home.write("large.json", Data(repeating: 0x20, count: InventoryFileIO.maxJSONBytes + 1))
        guard case .tooLarge = InventoryFileIO.readJSON(oversized) else { Issue.record("oversized file must remain too large"); return }
    }

    // MARK: LogFiles and a symlinked Claude root

    /// A real folder with a link to it, both inside one temp home (TempHome resolves its own root, so the link is built here).
    private func linkedClaude(_ home: TempHome) throws -> (real: URL, link: URL) {
        let real = home.url("dotfiles/claude")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = home.url("linked-claude")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return (real, link)
    }

    @Test("walk returns paths under the folder as given, even when that folder is a symlink")
    func walkKeepsGivenBase() throws {
        let home = try TempHome()
        let (_, link) = try linkedClaude(home)
        try home.write("dotfiles/claude/projects/-p/s1.jsonl", "{}\n")
        let found = LogFiles.walk(link.appendingPathComponent("projects"))
        #expect(found.map(\.path) == [link.appendingPathComponent("projects/-p/s1.jsonl").path])
    }

    @Test("a symlinked Claude root still gives its sessions a state and a tool")
    func symlinkedClaudeRoot() async throws {
        let sb = try ActivitySandbox()
        let (_, link) = try linkedClaude(sb.home)
        let sid = activitySid(1)
        let c = ClaudeRecords(cwd: "/work/app", session: sid)
        let records = [c.user("Build it", activityNowMs - 60_000), c.tool("b1", "Bash", ["command": "sleep 1"], activityNowMs - 50_000, usage: nil)]
        try sb.put("dotfiles/claude/projects/-work-app/\(sid).jsonl", records.map(activityJSON).joined(separator: "\n") + "\n", ageMs: 1000)
        var status: [String: Any] = [
            "pid": 1, "sessionId": sid, "cwd": "/work/app", "startedAt": activityNowMs - 3_600_000,
            "procStart": "Mon Nov  2 11:00:00 2026", "status": "busy", "name": "app-1", "nameSource": "derived", "statusUpdatedAt": activityNowMs - 3_000_000,
        ]
        status["pid"] = 1
        try sb.put("dotfiles/claude/sessions/1.json", activityJSON(status))
        var env = sb.home.env
        env["CLAUDE_CONFIG_DIR"] = link.path
        let roots = try Roots.resolve(env: env)
        let report = await readActivity(roots: roots, now: activityNow, proc: FakeProcess(alive: [1]))
        let found = try #require(session(report, sid))
        #expect(found.state == .running)
        #expect(found.currentTool?.name == "Bash")
    }

    // MARK: Inaccessible paths

    private func requireNotRoot() throws { try #require(geteuid() != 0, "root ignores permission bits") }

    @Test("a hook whose script sits under a folder that denies the lookup is not dead, and a problem says so")
    func deniedScriptIsNotDead() throws {
        try requireNotRoot()
        let home = try TempHome()
        let locked = home.url("locked")
        try home.write("locked/hook.sh", "echo hi\n")
        try home.write(".claude/settings.json", """
        {"hooks": {"Stop": [{"hooks": [
          {"type": "command", "command": "sh '\(locked.path)/hook.sh'"},
          {"type": "command", "command": "sh '\(home.root.path)/gone/missing.sh'"}
        ]}]}}
        """)
        chmod(0o000, locked)
        defer { chmod(0o755, locked) }
        let snapshot = Inventory.read(roots: try Roots.resolve(env: home.env))
        #expect(snapshot.hooks.map(\.dead) == [false, true])
        let notes = snapshot.problems.filter { $0.contains("cannot be checked") }
        #expect(notes.count == 1)
        #expect(!notes.joined().contains("hook.sh"), "the note names the settings file, not the script")
    }

    @Test("presence: only ENOENT and ENOTDIR mean missing")
    func presenceKinds() throws {
        try requireNotRoot()
        let home = try TempHome()
        try home.write("a/file.txt", "x")
        #expect(InventoryFileIO.presence(home.url("a/file.txt").path) == .present)
        #expect(InventoryFileIO.presence(home.url("a/none.txt").path) == .missing)
        #expect(InventoryFileIO.presence(home.url("a/file.txt/below").path) == .missing)
        chmod(0o000, home.url("a"))
        defer { chmod(0o755, home.url("a")) }
        #expect(InventoryFileIO.presence(home.url("a/file.txt").path) == .unknown)
        #expect(!InventoryFileIO.exists(home.url("a/file.txt").path))
    }

    @Test("a project under a folder Reins cannot stat is listed and reported as not readable, not dropped")
    func deniedProject() throws {
        try requireNotRoot()
        let home = try TempHome()
        let project = home.url("work/proj")
        try home.write("work/proj/.claude/skills/s/SKILL.md", "---\nname: s\n---\n")
        try home.write(".claude/projects/-enc-proj/s1.jsonl", "{\"type\":\"user\",\"cwd\":\"\(project.path)\"}\n")
        let roots = try Roots.resolve(env: home.env)
        #expect(Inventory.discoverProjects(roots: roots) == [project.path])

        chmod(0o000, project)
        defer { chmod(0o755, project) }
        #expect(Inventory.discoverProjects(roots: roots) == [project.path])
        let snapshot = Inventory.read(roots: roots)
        #expect(snapshot.problems.contains { $0.hasPrefix(project.path) && $0.contains("cannot be read") })
        #expect(snapshot.items.isEmpty)
    }

    // MARK: TOML nesting

    /// Runs `body` on a thread with a small stack, so unbounded recursion would crash here the way it would in the app.
    private func onSmallStack<T: Sendable>(_ body: @escaping @Sendable () -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        let box = Box<T>()
        let thread = Thread {
            box.value = body()
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        done.wait()
        return box.value!
    }

    private final class Box<T>: @unchecked Sendable { var value: T? }

    @Test("100000 nested brackets or braces are skipped, not recursed into")
    func deepToml() {
        let brackets = "a = " + String(repeating: "[", count: 100_000) + "\nb = 1\n"
        let braces = "a = " + String(repeating: "{ x = ", count: 100_000) + "\nb = 2\n"
        let docs = onSmallStack { (TOMLReader.read(brackets), TOMLReader.read(braces)) }
        #expect(docs.0.value([], "b") == .integer(1))
        #expect(docs.1.value([], "b") == .integer(2))
        #expect(docs.0.skippedLines >= 1 && docs.1.skippedLines >= 1)
    }

    @Test("nesting up to 64 levels reads; one more does not; ordinary nested values are unaffected")
    func tomlDepthLimit() {
        func nested(_ levels: Int) -> String { "a = " + String(repeating: "[", count: levels) + String(repeating: "]", count: levels) }
        #expect(TOMLReader.read(nested(64)).value([], "a") != nil)
        let over = TOMLReader.read(nested(65))
        #expect(over.value([], "a") == nil)
        #expect(over.entries.count == 1, "the key still counts as present")
        let doc = TOMLReader.read("a = [[1, 2], [3, [4]]]\nt = { x = [1, { y = 2 }] }\n")
        #expect(doc.value([], "a") == .array([.array([.integer(1), .integer(2)]), .array([.integer(3), .array([.integer(4)])])]))
        #expect(doc.value([], "t")?["x"]?.arrayValue?.count == 2)
    }

    // MARK: Compressed logs

    @Test("a stream of 200000 short lines is read with only about maxBytes of lines held")
    func ringBufferBoundsMemory() throws {
        let home = try TempHome()
        var text = Data()
        for n in 0..<200_000 { text.append(contentsOf: Array("{\"i\":\(n)}\n".utf8)) }
        let file = try home.write("many.jsonl.zst", ZstdFrame.raw(text))
        let reader = CompressedLogReader(url: file, maxBytes: 10_000)
        var seen: [String] = []
        let result = try reader.read({ seen.append(String(decoding: $0, as: UTF8.self)) })
        #expect(result.truncated)
        #expect(seen.last == "{\"i\":199999}")
        #expect(seen.count > 500 && seen.count < 1000)
        #expect(result.lines == seen.count)
        #expect(reader.peakStoredLines < 4000, "held \(reader.peakStoredLines) lines at the peak out of 200000")
    }

    @Test("LineTail keeps at least one line and drops the oldest first")
    func lineTail() {
        var tail = LineTail(maxBytes: 10)
        tail.append(Data(repeating: 0x61, count: 50))
        #expect(tail.count == 1 && !tail.dropped)
        tail.append(Data(repeating: 0x62, count: 4))
        tail.append(Data(repeating: 0x63, count: 4))
        var seen: [Data] = []
        tail.forEach { seen.append($0) }
        #expect(seen.map(\.count) == [4, 4])
        #expect(tail.dropped && tail.bytes == 8)
    }

    @Test("a dropped line over the length cap marks the read truncated")
    func oversizedLineIsTruncated() throws {
        let home = try TempHome()
        let long = "{\"x\":\"" + String(repeating: "a", count: 300) + "\"}\n"
        let file = try home.write("long.jsonl.zst", ZstdFrame.raw(Data((long + "{\"a\":1}\n").utf8)))
        var seen = 0
        let result = try CompressedLogReader(url: file, maxLineBytes: 100).read({ _ in seen += 1 })
        #expect(seen == 1 && result.oversizedLines == 1)
        #expect(result.truncated)
    }

    @Test("a small file that expands past the output cap throws tooLarge")
    func decompressionCap() throws {
        let home = try TempHome()
        let bomb = ZstdFrame.repeated(0x78, count: 4 * 1024 * 1024)
        let file = try home.write("bomb.jsonl.zst", bomb)
        #expect(bomb.count < 200)
        let stream = try ZstdStream(url: file, maxOutputBytes: 1_000_000)
        #expect(throws: ZstdError.tooLarge) { try stream.forEachChunk { _ in } }
        // Within the cap the same file reads fine.
        var total = 0
        try ZstdStream(url: file, maxOutputBytes: 8 * 1024 * 1024).forEachChunk { total += $0.count }
        #expect(total == 4 * 1024 * 1024)
    }

    @Test("the default cap stops a 600 MB expansion for the reader, and a second poll of the same file fails at once")
    func readerDefaultCap() throws {
        let home = try TempHome()
        let file = try home.write("bomb.jsonl.zst", ZstdFrame.repeated(0x78, count: 600 * 1024 * 1024))
        let reader = CompressedLogReader(url: file)
        #expect(throws: ZstdError.tooLarge) { _ = try reader.read({ _ in }) }
        let again = Date()
        #expect(throws: ZstdError.tooLarge) { _ = try reader.read({ _ in }) }
        #expect(Date().timeIntervalSince(again) < 0.5, "the same unchanged file is not decompressed again")
    }

    private struct DiskError: Error, Equatable {}

    @Test("an I/O error while reading the input is rethrown, not taken for the end of the file")
    func ioErrorRethrown() throws {
        let stream = try ZstdStream(readInput: { _ in throw DiskError() })
        #expect(throws: DiskError()) { _ = try stream.nextChunk() }
        // A real file cannot be made to fail a read portably; this is the same path with the read replaced.
        let good = ZstdFrame.raw(Data("{\"a\":1}\n".utf8))
        var served = false
        let flaky = try ZstdStream(readInput: { _ in
            if served { throw DiskError() }
            served = true
            return good.prefix(good.count - 2)
        })
        #expect(throws: DiskError()) { try flaky.forEachChunk { _ in } }
    }

    @Test("a stream whose size is an exact multiple of the output buffer is not reported as truncated")
    func exactBlockMultiple() throws {
        let home = try TempHome()
        let file = try home.write("aligned.jsonl.zst", ZstdFrame.repeated(0x78, count: 2 * ZstdFrame.blockMax))
        var total = 0
        try ZstdStream(url: file).forEachChunk { total += $0.count }
        #expect(total == 2 * ZstdFrame.blockMax)
    }

    // MARK: Process adapter

    @Test("merge: a pid without a lock has no thread, and a pid with locks is not repeated")
    func mergeThreads() {
        let locks = [CodexThread(pid: 10, threadId: activityUuid(1)), CodexThread(pid: 10, threadId: activityUuid(2)), CodexThread(pid: 12, threadId: activityUuid(3))]
        let merged = ProcessOutputParser.merge(pids: [10, 11, 12, 13], locks: locks)
        #expect(merged == locks + [CodexThread(pid: 11, threadId: nil), CodexThread(pid: 13, threadId: nil)])
        #expect(merged.filter { $0.pid == 10 }.count == 2)
        #expect(ProcessOutputParser.merge(pids: [], locks: []).isEmpty)
        #expect(ProcessOutputParser.merge(pids: [5], locks: []) == [CodexThread(pid: 5, threadId: nil)])
    }

    @Test("stopSession turns an unexpected signal error into a 500 with the error number")
    func signalFailureIs500() async throws {
        let sb = try ActivitySandbox()
        try sb.status(15, ["procStart": "Mon Nov  2 11:00:00 2026"])
        let proc = FakeProcess(alive: [15], starts: [15: "Mon Nov  2 11:00:00 2026"], terminateError: .failed(errno: EIO))
        do {
            _ = try await stopSession(roots: try sb.roots, cli: .claude, id: activitySid(15), proc: proc, options: StopOptions(waitMs: 30, pollMs: 5))
            Issue.record("expected a 500")
        } catch {
            let failure = try #require(error as? ReinsError)
            #expect(failure.status == 500)
            #expect(failure.message == "The session could not be stopped (error \(EIO)).")
        }
    }
}
