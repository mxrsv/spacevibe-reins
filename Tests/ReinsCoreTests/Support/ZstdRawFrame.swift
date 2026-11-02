import Foundation

/// A zstd frame made of one raw (uncompressed) block: valid zstd, no compressor needed. Single segment, 4-byte content size.
func zstdRawFrame(_ payload: Data) -> Data {
    precondition(payload.count < 128 * 1024)
    var out = Data([0x28, 0xB5, 0x2F, 0xFD, 0xA0])
    withUnsafeBytes(of: UInt32(payload.count).littleEndian) { out.append(contentsOf: $0) }
    let header = UInt32(payload.count) << 3 | 1  // last block, type raw
    out.append(contentsOf: [UInt8(header & 0xFF), UInt8((header >> 8) & 0xFF), UInt8((header >> 16) & 0xFF)])
    out.append(payload)
    return out
}
