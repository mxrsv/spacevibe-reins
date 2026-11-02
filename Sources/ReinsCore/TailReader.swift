import Foundation

/// What one `read` found out about the file.
public struct LogReadResult: Equatable, Sendable {
    /// The file does not exist (yet, or any more).
    public var missing = false
    public var size = 0
    public var modified: Date?
    /// The first read started inside the file because of `maxBytes`; earlier records were not read.
    public var truncated = false
    /// The file was replaced or shrank, so reading restarted at the beginning and `onReset` was called.
    public var didReset = false
    /// Lines passed to `onLine` by this read.
    public var lines = 0
    /// Lines skipped because they do not look like a JSON object. Counted in total in `TailReader.invalidLines`.
    public var invalidLines = 0
    /// Lines skipped because they were longer than the cap.
    public var oversizedLines = 0
}

/// Reads the lines of a JSONL log that were added since the last read.
public protocol LogReader: AnyObject {
    /// Calls `onLine` with each new complete, non-blank record line. `onReset` is called first when the file was replaced
    /// or truncated and everything will be read again from the start.
    @discardableResult
    func read(_ onLine: (Data) -> Void, onReset: () -> Void) throws -> LogReadResult
}

public extension LogReader {
    @discardableResult
    func read(_ onLine: (Data) -> Void) throws -> LogReadResult { try read(onLine, onReset: {}) }
}

/// `st_mtimespec` on Darwin, `st_mtim` elsewhere.
func modificationTime(_ info: stat) -> timespec {
    #if canImport(Darwin)
    return info.st_mtimespec
    #else
    return info.st_mtim
    #endif
}

public enum LogReadError: Error, Equatable, Sendable {
    /// open, stat or read failed; the number is `errno`. Never carries file content.
    case cannotRead(errno: Int32)
}

/// Incremental, read-only line reader for plain `.jsonl` logs. It remembers its byte offset, so a second `read` returns
/// only what was appended. The file's identity is device plus inode: a log that is deleted and recreated is read again
/// from the start, and so is one that shrank. A last line without its newline is held back until the newline arrives.
///
/// Lines that do not start with `{` and end with `}` are not passed on: they are counted in `invalidLines`. The check is
/// a cheap shape test; a consumer whose own parse fails calls `noteInvalidLine()` to add to the same count.
public final class TailReader: LogReader {
    public static let chunkBytes = 256 * 1024
    public static let defaultMaxLineBytes = 16 * 1024 * 1024

    public let url: URL
    private let maxBytes: Int
    private let maxLineBytes: Int
    private let requireObjectShape: Bool

    public private(set) var offset = 0
    /// Lines skipped as not-an-object since this reader was created (not reset by a file reset).
    public private(set) var invalidLines = 0
    public private(set) var oversizedLines = 0
    private var identity: String?
    private var partial = Data()
    private var skipping = false
    private var truncated = false

    /// - Parameters:
    ///   - maxBytes: on the first read of a larger file, start this many bytes before the end (the first partial line is dropped).
    ///   - maxLineBytes: longer lines are skipped.
    ///   - requireObjectShape: pass only lines that look like a JSON object.
    public init(url: URL, maxBytes: Int = .max, maxLineBytes: Int = TailReader.defaultMaxLineBytes, requireObjectShape: Bool = true) {
        self.url = url
        self.maxBytes = maxBytes
        self.maxLineBytes = maxLineBytes
        self.requireObjectShape = requireObjectShape
    }

    /// For a consumer whose own JSON parse of a passed line failed.
    public func noteInvalidLine() { invalidLines += 1 }

    private func reset() {
        offset = 0
        identity = nil
        partial.removeAll()
        skipping = false
        truncated = false
    }

    @discardableResult
    public func read(_ onLine: (Data) -> Void, onReset: () -> Void = {}) throws -> LogReadResult {
        let fd = open(url.path, O_RDONLY)
        if fd < 0 {
            if errno == ENOENT { return LogReadResult(missing: true) }
            throw LogReadError.cannotRead(errno: errno)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw LogReadError.cannotRead(errno: errno) }

        var result = LogReadResult()
        let size = Int(info.st_size)
        let newIdentity = "\(info.st_dev):\(info.st_ino)"
        if (identity != nil && newIdentity != identity) || size < offset {
            reset()
            onReset()
            result.didReset = true
        }
        identity = newIdentity
        if offset == 0, size > maxBytes {
            offset = size - maxBytes
            skipping = true
            truncated = true
        }

        let invalidBefore = invalidLines
        let oversizedBefore = oversizedLines
        var buffer = [UInt8](repeating: 0, count: Self.chunkBytes)
        while offset < size {
            let wanted = min(Self.chunkBytes, size - offset)
            let got = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, wanted, off_t(offset)) }
            if got < 0 { throw LogReadError.cannotRead(errno: errno) }
            if got == 0 { break }
            offset += got
            consume(buffer[0..<got], onLine, count: &result.lines)
        }
        result.size = size
        let mtime = modificationTime(info)
        result.modified = Date(timeIntervalSince1970: TimeInterval(mtime.tv_sec) + TimeInterval(mtime.tv_nsec) / 1e9)
        result.truncated = truncated
        result.invalidLines = invalidLines - invalidBefore
        result.oversizedLines = oversizedLines - oversizedBefore
        return result
    }

    private func consume(_ bytes: ArraySlice<UInt8>, _ onLine: (Data) -> Void, count: inout Int) {
        var start = bytes.startIndex
        while let newline = bytes[start...].firstIndex(of: 0x0A) {
            if skipping {
                skipping = false
                partial.removeAll(keepingCapacity: true)
            } else {
                var line = partial
                line.append(contentsOf: bytes[start..<newline])
                partial.removeAll(keepingCapacity: true)
                emit(line, onLine, count: &count)
            }
            start = newline + 1
        }
        guard start < bytes.endIndex, !skipping else { return }
        partial.append(contentsOf: bytes[start...])
        if partial.count > maxLineBytes {
            partial.removeAll(keepingCapacity: true)
            skipping = true
            oversizedLines += 1
        }
    }

    private func emit(_ line: Data, _ onLine: (Data) -> Void, count: inout Int) {
        if line.count > maxLineBytes { oversizedLines += 1; return }
        guard let first = line.first(where: { !Self.isBlank($0) }) else { return }
        if requireObjectShape {
            let last = line.last(where: { !Self.isBlank($0) })
            guard first == UInt8(ascii: "{"), last == UInt8(ascii: "}") else { invalidLines += 1; return }
        }
        count += 1
        onLine(line)
    }

    fileprivate static func isBlank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0D }
}

/// The same `read` for a `.zst` log. It cannot seek or be appended to, so it reads the whole file once and again only when
/// the file changes (device, inode, size or mtime), calling `onReset` before the second full read. `maxBytes` keeps the last
/// lines up to about that many bytes, as `TailReader` does by starting late.
public final class CompressedLogReader: LogReader {
    public let url: URL
    private let maxBytes: Int
    private let maxLineBytes: Int
    public private(set) var invalidLines = 0
    private var stamp: String?
    private var tooLargeStamp: String?
    private var truncated = false
    /// The most lines held at once during the last full read. Bounded by `maxBytes`, not by the file's line count.
    private(set) var peakStoredLines = 0

    public init(url: URL, maxBytes: Int = .max, maxLineBytes: Int = TailReader.defaultMaxLineBytes) {
        self.url = url
        self.maxBytes = maxBytes
        self.maxLineBytes = maxLineBytes
    }

    public func noteInvalidLine() { invalidLines += 1 }

    @discardableResult
    public func read(_ onLine: (Data) -> Void, onReset: () -> Void = {}) throws -> LogReadResult {
        var info = stat()
        if stat(url.path, &info) != 0 {
            if errno == ENOENT { return LogReadResult(missing: true) }
            throw LogReadError.cannotRead(errno: errno)
        }
        var result = LogReadResult()
        result.size = Int(info.st_size)
        let mtime = modificationTime(info)
        result.modified = Date(timeIntervalSince1970: TimeInterval(mtime.tv_sec) + TimeInterval(mtime.tv_nsec) / 1e9)
        let newStamp = "\(info.st_dev):\(info.st_ino):\(info.st_size):\(mtime.tv_sec).\(mtime.tv_nsec)"
        if newStamp == stamp {
            result.truncated = truncated
            return result
        }
        // A bomb is not decompressed again on every poll: the same file fails the same way until it changes.
        if newStamp == tooLargeStamp { throw ZstdError.tooLarge }
        if stamp != nil {
            onReset()
            result.didReset = true
        }

        // maxBytes counts UTF-8 bytes, like TailReader. core/tail-reader.mjs counts UTF-16 units; the two agree on ASCII logs.
        var tail = LineTail(maxBytes: maxBytes)
        var invalid = 0
        let oversized: Int
        do {
            oversized = try LogFiles.forEachLine(at: url, maxLineBytes: maxLineBytes) { line in
                guard let first = line.first(where: { !TailReader.isBlank($0) }) else { return }
                guard first == UInt8(ascii: "{"), line.last(where: { !TailReader.isBlank($0) }) == UInt8(ascii: "}") else { invalid += 1; return }
                tail.append(line)
            }
        } catch ZstdError.tooLarge {
            tooLargeStamp = newStamp
            throw ZstdError.tooLarge
        }
        tail.forEach(onLine)
        // A dropped line over the cap counts as truncated, as in Node.
        let didDrop = tail.dropped || oversized > 0
        stamp = newStamp
        truncated = didDrop
        invalidLines += invalid
        peakStoredLines = tail.peakStored
        result.lines = tail.count
        result.invalidLines = invalid
        result.oversizedLines = oversized
        result.truncated = didDrop
        return result
    }
}

/// The last lines of a stream, up to about `maxBytes` (never fewer than one line). Evicted lines are released at once
/// and the array is compacted, so memory follows `maxBytes` however many lines pass through.
struct LineTail {
    let maxBytes: Int
    private var storage: [Data] = []
    private var head = 0
    private(set) var bytes = 0
    private(set) var dropped = false
    /// The most slots `storage` ever held, evicted ones included: what a test asserts to show memory stayed bounded.
    private(set) var peakStored = 0

    init(maxBytes: Int) { self.maxBytes = maxBytes }

    var count: Int { storage.count - head }

    mutating func append(_ line: Data) {
        storage.append(line)
        bytes += line.count
        while bytes > maxBytes, count > 1 {
            bytes -= storage[head].count
            storage[head] = Data()
            head += 1
            dropped = true
        }
        if head >= 1024, head * 2 >= storage.count {
            storage.removeFirst(head)
            head = 0
        }
        peakStored = max(peakStored, storage.count)
    }

    func forEach(_ body: (Data) -> Void) { storage[head...].forEach(body) }
}
