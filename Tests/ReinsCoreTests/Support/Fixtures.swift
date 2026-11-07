import CryptoKit
import Foundation

/// Committed test data under core/testdata/fixtures (frozen goldens (SV5), last generated at b58269d3f3eb).
enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("core/testdata/fixtures", isDirectory: true)

    static func url(_ relative: String) -> URL { directory.appendingPathComponent(relative) }

    static func data(_ relative: String) throws -> Data { try Data(contentsOf: url(relative)) }

    static func json(_ relative: String) throws -> Any {
        try JSONSerialization.jsonObject(with: data(relative))
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
