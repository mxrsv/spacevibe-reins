import Foundation

/// The protocol-level shapes: the `initialize` handshake and the JSON-RPC error envelope. The engine shapes are in the
/// other `CoreTypes*.swift` files.
enum CoreProtocol {
    /// `protocolVersion` of `initialize`: the integer 1. Any other value is -32001.
    static let version = 1
    /// Prefix of every environment variable the product reads (SV12). The core reports the same value in `initialize`; a
    /// test holds the two equal. The app does not import the engine for it.
    static let envPrefix = "SPACEVIBE_"
}

struct CoreClientInfo: Codable, Equatable, Sendable {
    let name: String
    let version: String
}

/// The result of `initialize`. The shell takes the core's name, version, env prefix and data folder from it (SV12).
struct CoreInitializeResult: Codable, Equatable, Sendable {
    struct Core: Codable, Equatable, Sendable {
        let name: String
        let version: String
    }

    struct Identity: Codable, Equatable, Sendable {
        let envPrefix: String
        let dataDir: String
    }

    let protocolVersion: Int
    let core: Core
    let identity: Identity
    /// Every method the core registered, sorted.
    let methods: [String]
}

/// A JSON-RPC error object. `data` depends on the code: `{status, message}` for -32000 (see `coreError`),
/// `{protocolVersion}` for -32001, none for the rest.
struct CoreRPCError: Codable, Equatable, Sendable {
    struct Details: Codable, Equatable, Sendable {
        let status: Int?
        let message: String?
        let protocolVersion: Int?
    }

    let code: Int
    let message: String
    let data: Details?

    /// The engine's refusal, for a -32000 whose `data` carries `{status, message}`.
    var coreError: CoreError? {
        guard let data, let status = data.status, let message = data.message else { return nil }
        return CoreError(status: status, message: message)
    }
}
