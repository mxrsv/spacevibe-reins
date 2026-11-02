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
}

/// Reads a `.zst` file as a sequence of decompressed chunks (concatenated frames are one stream).
/// Memory stays at one input and one output buffer, whatever the file size.
public final class ZstdStream {
    private let handle: FileHandle
    private let context: OpaquePointer
    private let inputSize = ZSTD_DStreamInSize()
    private let outputSize = ZSTD_DStreamOutSize()
    private var input: [UInt8] = []
    private var inputPosition = 0
    private var inputDone = false
    private var insideFrame = false
    private var outputMayBePending = false

    public init(url: URL) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ZstdError.cannotOpen }
        guard let context = ZSTD_createDCtx() else {
            try? handle.close()
            throw ZstdError.cannotCreateContext
        }
        self.handle = handle
        self.context = context
    }

    deinit {
        ZSTD_freeDCtx(context)
        try? handle.close()
    }

    /// The next decompressed bytes, or nil at the end of the file.
    public func nextChunk() throws -> Data? {
        while true {
            if inputPosition >= input.count && !outputMayBePending {
                if inputDone {
                    if insideFrame { throw ZstdError.truncated }
                    return nil
                }
                let bytes = (try? handle.read(upToCount: inputSize)) ?? Data()
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
            insideFrame = result != 0
            outputMayBePending = produced == outputSize
            if produced > 0 { return Data(output[0..<produced]) }
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
