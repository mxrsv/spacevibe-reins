import Foundation

/// Cuts the core's stdout into lines. Each chunk is searched for the newline once, so a line of many MiB costs the same as
/// its bytes, not the square of its chunks; one line is capped at `maxLine`, so a stream with no newline cannot grow without bound.
struct CoreLineFramer {
    /// The documented response cap (64 MiB, docs/internals/core-protocol.md) plus room for the envelope around the result.
    static let maxLine = 64 * 1024 * 1024 + 1024 * 1024

    /// One line passed `maxLine`. The session is over: nothing after it can be trusted to be on a line boundary.
    struct Overflow: Error {}

    /// The bytes of the line that has not ended yet.
    private var partial = Data()

    var bufferedCount: Int { partial.count }

    /// Takes the first `count` bytes of `chunk` and returns the lines it completed, without their newline. Blank lines are dropped.
    mutating func feed(_ chunk: [UInt8], count: Int) throws -> [Data] {
        var lines: [Data] = []
        try chunk.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var start = 0
            while start < count {
                let rest = base + start
                let hit = memchr(rest, 0x0A, count - start)
                let end = hit.map { start + (UnsafeRawPointer($0) - rest) } ?? count
                guard partial.count + (end - start) <= Self.maxLine else {
                    partial = Data()
                    throw Overflow()
                }
                partial.append(rest.assumingMemoryBound(to: UInt8.self), count: end - start)
                guard hit != nil else { return }
                if !partial.isEmpty { lines.append(partial) }
                partial = Data()
                start = end + 1
            }
        }
        return lines
    }
}
