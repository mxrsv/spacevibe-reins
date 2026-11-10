import Foundation

/// JSON-RPC 2.0 over NDJSON: the lines `CoreClient` writes and the envelopes it reads (docs/internals/core-protocol.md,
/// "Framing and lifecycle").
enum CoreWire {
    /// Params of a method that takes none: the object `{}`.
    struct NoParams: Encodable {}

    private struct Request<P: Encodable>: Encodable {
        let jsonrpc = "2.0"
        let id: Int?
        let method: String
        let params: P
    }

    /// One request line, with its newline. A notification has no id.
    static func line(id: Int?, method: String, params: some Encodable) throws -> Data {
        var data = try JSONEncoder().encode(Request(id: id, method: method, params: params))
        data.append(0x0A)
        return data
    }

    /// The part of any incoming line that routes it: a response has an `id` and no `method`, a notification has a `method`.
    struct Envelope: Decodable {
        let id: Int?
        let method: String?
        let error: CoreRPCError?

        private enum Keys: String, CodingKey { case id, method, error }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            // The client only sends integer ids; a response with another kind of id (the core echoes them) matches nothing.
            id = try? container.decodeIfPresent(Int.self, forKey: .id)
            method = try container.decodeIfPresent(String.self, forKey: .method)
            error = try container.decodeIfPresent(CoreRPCError.self, forKey: .error)
        }
    }

    struct Reply<Result: Decodable>: Decodable {
        let result: Result
    }

    struct Note<Params: Decodable>: Decodable {
        let params: Params
    }

    /// The `usage/progress` params: the DTO plus the id of the `usage.scan` request.
    struct ProgressParams: Decodable {
        let id: Int
        let done: Int
        let total: Int
    }

    static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }

    static func reply<R: Decodable>(_ type: R.Type, from line: Data) throws -> R {
        try decode(Reply<R>.self, from: line).result
    }

    // MARK: Errors

    static let cancelledCode = -32800
    static let versionMismatchCode = -32001

    /// The error the screens see for a JSON-RPC error. -32000 is the engine's own refusal (its message is safe to show);
    /// any other code is a protocol fault whose text stays out of the UI (S-R3).
    static func error(from rpc: CoreRPCError) -> Error {
        if rpc.code == cancelledCode { return CancellationError() }
        return rpc.coreError ?? CoreError(protocolFaultMessage, status: 500)
    }

    static let protocolFaultMessage = "The SpaceVibe helper reported an internal problem."
    static let undecodableMessage = "The SpaceVibe helper sent an answer this version of SpaceVibe does not understand."
    static let restartedMessage = "The SpaceVibe helper restarted before it answered, so this may not have been done. Check the list and try again."
    static let startFailedMessage = "The SpaceVibe helper could not be started."
    static let incompatibleMessage = "This copy of SpaceVibe and its helper do not match. Reinstall SpaceVibe."
    static let closedMessage = "The SpaceVibe helper was shut down."
}

/// A JSON-RPC error that reached the session's caller as it came; `CoreConnection` maps it.
struct CoreRPCFailure: Error {
    let error: CoreRPCError
}
