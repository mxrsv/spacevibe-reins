import Foundation

/// An error the core reports: `data` of a JSON-RPC -32000 (docs/internals/core-protocol.md, "Errors"). It replaces
/// `ReinsError` in the screens' error handling. `status` follows HTTP: 400 bad input, 403 refused, 404 gone, 409
/// conflicts with the current state, 413 too large, 500 the write failed. `message` is safe to show: it may name a path
/// or a rule, never file content (S-R3).
struct CoreError: Error, Equatable, Sendable, Codable, LocalizedError, CustomStringConvertible {
    let status: Int
    let message: String

    var errorDescription: String? { message }
    var description: String { message }
}

extension CoreError {
    /// The same call shape as `ReinsError(_:status:)`, which this replaces.
    init(_ message: String, status: Int = 400) {
        self.init(status: status, message: message)
    }

    /// What `AppEnvironment.message` shows for an error that is not the core's own (S-R3: never its description).
    static let unexpectedMessage = "The change could not be made."
}
