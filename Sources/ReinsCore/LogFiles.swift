import Foundation

/// Finding and opening session logs. Older Codex rollouts sit on disk as `.jsonl.zst`, so a reader that only knows `.jsonl`
/// silently loses most of a machine's Codex history. Same naming rule as core/log-files.mjs.
public enum LogFiles {
    private static let readChunk = 1 << 20

    /// `x.jsonl`, `x.jsonl.zst` and `x.jsonl.zstd`.
    public static func isLog(_ name: String) -> Bool { stripLogSuffix(name) != nil }

    /// `.zst` or `.zstd` at the end.
    public static func isCompressed(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasSuffix(".zst") || name.hasSuffix(".zstd")
    }

    /// The file name without `.jsonl` or `.jsonl.zst`, so both forms of one session share a name.
    public static func baseName(_ url: URL) -> String {
        let name = url.lastPathComponent
        return stripLogSuffix(name) ?? name
    }

    private static func stripLogSuffix(_ name: String) -> String? {
        for suffix in [".jsonl.zstd", ".jsonl.zst", ".jsonl"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return nil
    }

    /// Every log under `directory`, sorted by path. When a session exists in both forms in one folder, only the plain
    /// `.jsonl` is listed: it is the one still written. Symlinks are not followed. A folder that cannot be read counts as empty.
    public static func walk(_ directory: URL) -> [URL] {
        var out: [URL] = []
        collect(directory, into: &out)
        return out.sorted { $0.path < $1.path }
    }

    private static func collect(_ directory: URL, into out: inout [URL]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: []) else { return }
        let names = Set(entries.map(\.lastPathComponent))
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
            if values.isDirectory == true {
                collect(entry, into: &out)
            } else if values.isRegularFile == true, let base = stripLogSuffix(entry.lastPathComponent) {
                if isCompressed(entry), names.contains("\(base).jsonl") { continue }
                out.append(entry)
            }
        }
    }

    /// Calls `body` with the log's bytes in chunks, decompressing `.zst`. Throws `ZstdError` or a file error.
    public static func forEachChunk(at url: URL, _ body: (Data) throws -> Void) throws {
        if isCompressed(url) {
            try ZstdStream(url: url).forEachChunk(body)
            return
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: readChunk), !chunk.isEmpty { try body(chunk) }
    }

    /// Calls `body` with each line of the log, without its `\n` (a trailing `\r` is kept). Empty lines are passed too;
    /// a last line without a newline is passed. Lines longer than `maxLineBytes` are skipped and counted in the result.
    /// - Returns: how many lines were skipped for length.
    @discardableResult
    public static func forEachLine(at url: URL, maxLineBytes: Int = .max, _ body: (Data) throws -> Void) throws -> Int {
        var splitter = LineSplitter(maxLineBytes: maxLineBytes)
        try forEachChunk(at: url) { chunk in try splitter.feed(chunk, body) }
        try splitter.finish(body)
        return splitter.oversized
    }

    /// A reader for the log that picks the right class: `TailReader` for plain files, `CompressedLogReader` for `.zst`.
    public static func reader(for url: URL, maxBytes: Int = .max) -> any LogReader {
        isCompressed(url) ? CompressedLogReader(url: url, maxBytes: maxBytes) : TailReader(url: url, maxBytes: maxBytes)
    }
}

/// Splits a byte stream into lines across chunk boundaries. Works on bytes, so a multi-byte character cut by a chunk is safe.
struct LineSplitter {
    let maxLineBytes: Int
    private(set) var oversized = 0
    private var partial = Data()
    private var skipping = false

    init(maxLineBytes: Int) { self.maxLineBytes = maxLineBytes }

    mutating func feed(_ chunk: Data, _ body: (Data) throws -> Void) throws {
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            if skipping {
                skipping = false
                partial.removeAll(keepingCapacity: true)
            } else if partial.isEmpty {
                try emit(chunk[start..<newline], body)
            } else {
                partial.append(chunk[start..<newline])
                let line = partial
                partial.removeAll(keepingCapacity: true)
                try emit(line[...], body)
            }
            start = newline + 1
        }
        guard start < chunk.endIndex, !skipping else { return }
        partial.append(chunk[start...])
        if partial.count > maxLineBytes {
            partial.removeAll(keepingCapacity: true)
            skipping = true
            oversized += 1
        }
    }

    mutating func finish(_ body: (Data) throws -> Void) throws {
        if !skipping, !partial.isEmpty { try emit(partial[...], body) }
        partial.removeAll()
        skipping = false
    }

    private mutating func emit(_ line: Data.SubSequence, _ body: (Data) throws -> Void) throws {
        if line.count > maxLineBytes { oversized += 1; return }
        try body(Data(line))
    }
}
