import CZstd
import Foundation

/// Why a compressed log could not be read. Never carries file content.
public enum ZstdError: Error, Equatable, Sendable {
    case cannotOpen
    case cannotCreateContext
    /// The zstd library's own error name, a fixed string such as "Unknown frame descriptor".
    case corrupt(String)
    /// The file ends inside a frame.
    case truncated
    /// The stream decompressed past its output cap (a tiny file that expands to gigabytes). Callers treat the log as unreadable.
    case tooLarge
}

/// Reads a `.zst` file as a sequence of decompressed chunks (concatenated frames are one stream).
/// Memory stays at one input and one output buffer, whatever the file size. The total decompressed size is capped
/// (`defaultMaxOutputBytes`), so a small file cannot keep a reader busy for gigabytes; past the cap `nextChunk` throws `.tooLarge`.
/// There is no wall-clock budget: the cap bounds the work, and a stream that stays under it decodes in seconds.
public final class ZstdStream {
    /// Far above any real session log (the largest on a heavy machine is tens of MB), far below a decompression bomb.
    public static let defaultMaxOutputBytes = 512 * 1024 * 1024

    private let maxOutputBytes: Int
    private var totalOutput = 0
    private let handle: FileHandle?
    /// The next input bytes (up to the count), empty at the end of the file. Throws on an I/O error.
    private let readInput: (Int) throws -> Data
    private let context: OpaquePointer
    private let inputSize = ZSTD_DStreamInSize()
    private let outputSize = ZSTD_DStreamOutSize()
    private var input: [UInt8] = []
    private var inputPosition = 0
    private var inputDone = false
    private var insideFrame = false
    private var outputMayBePending = false

    public init(url: URL, maxOutputBytes: Int = ZstdStream.defaultMaxOutputBytes) throws {
        self.maxOutputBytes = maxOutputBytes
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ZstdError.cannotOpen }
        guard let context = ZSTD_createDCtx() else {
            try? handle.close()
            throw ZstdError.cannotCreateContext
        }
        self.handle = handle
        self.context = context
        readInput = { try handle.read(upToCount: $0) ?? Data() }
    }

    /// For tests: a source that can fail the way a disk read can.
    init(readInput: @escaping (Int) throws -> Data) throws {
        guard let context = ZSTD_createDCtx() else { throw ZstdError.cannotCreateContext }
        maxOutputBytes = ZstdStream.defaultMaxOutputBytes
        handle = nil
        self.context = context
        self.readInput = readInput
    }

    deinit {
        ZSTD_freeDCtx(context)
        try? handle?.close()
    }

    /// The next decompressed bytes, or nil at the end of the file.
    public func nextChunk() throws -> Data? {
        while true {
            if inputPosition >= input.count && !outputMayBePending {
                if inputDone {
                    if insideFrame { throw ZstdError.truncated }
                    return nil
                }
                // An I/O error is rethrown: reading it as end of file would report a half-read log as complete.
                let bytes = try readInput(inputSize)
                if bytes.isEmpty { inputDone = true; continue }
                input = [UInt8](bytes)
                inputPosition = 0
            }

            var output = [UInt8](repeating: 0, count: outputSize)
            let consumedBefore = inputPosition
            var produced = 0
            var result = 0
            input.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { target in
                    var inBuffer = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: inputPosition)
                    var outBuffer = ZSTD_outBuffer(dst: target.baseAddress, size: target.count, pos: 0)
                    result = ZSTD_decompressStream(context, &outBuffer, &inBuffer)
                    inputPosition = inBuffer.pos
                    produced = outBuffer.pos
                }
            }
            if ZSTD_isError(result) != 0 {
                throw ZstdError.corrupt(String(cString: ZSTD_getErrorName(result)))
            }
            // With no input taken and none produced, the call only asked for the next frame's header: that is not "inside a frame".
            // (A stream whose size is an exact multiple of the output buffer ends with such a call.)
            if inputPosition > consumedBefore || produced > 0 { insideFrame = result != 0 }
            outputMayBePending = produced == outputSize
            if produced > 0 {
                totalOutput += produced
                if totalOutput > maxOutputBytes { throw ZstdError.tooLarge }
                return Data(output[0..<produced])
            }
            // No output and no input taken: the decoder cannot advance, so stop instead of spinning.
            if inputPosition == consumedBefore && inputPosition < input.count { throw ZstdError.corrupt("no progress") }
        }
    }

    /// Calls `body` for every decompressed chunk.
    public func forEachChunk(_ body: (Data) throws -> Void) throws {
        while let chunk = try nextChunk() { try body(chunk) }
    }

    /// The whole decompressed file in memory. For tests and small files; use `nextChunk` for logs.
    public static func readAll(url: URL) throws -> Data {
        var out = Data()
        try ZstdStream(url: url).forEachChunk { out.append($0) }
        return out
    }
}
