import Foundation

/// An error whose message is safe to show to the user. Same job as `UserError` in Node mutate (git b58269d).
///
/// The message may name a path or a rule, never file content: a parse error from a settings file can quote a secret,
/// so callers replace those with a fixed sentence. `status` follows HTTP: 400 bad input, 403 refused, 404 gone,
/// 409 conflict with the current state (the file changed, the file is not valid JSON), 413 too large, 500 the write failed.
public struct ReinsError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    public let message: String
    public let status: Int

    public init(_ message: String, status: Int = 400) {
        self.message = message
        self.status = status
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}
