import Foundation
import Testing
@testable import SpaceVibe

/// The CLIs the tests run against: the core's own `clis.list` reply, frozen in the `clis_list` RPC transcript, joined to the
/// app's look table. Every suite carries `.fixtureCLIs`, so `CLICatalog.current` is this catalog inside each test (and the tasks
/// it starts), and no test reads or changes the app's catalog. A test that needs other CLIs sets `CLICatalog.$scoped` itself.
enum CLICatalogFixture {
    /// Claude Code and Codex (installed, every concept) and Gemini CLI (limits only, not installed), in registry order.
    static let list: [CoreCLIInfo] = {
        do { return try decodeTranscriptList() } catch { fatalError("rpc/clis_list.jsonl: \(error)") }
    }()

    static let catalog = CLICatalog(list: list)

    static func info(_ id: CLIID) -> CoreCLIInfo {
        guard let info = list.first(where: { $0.id == id }) else { fatalError("no \(id) in the clis.list transcript") }
        return info
    }

    /// The first `clis.list` reply of the transcript.
    static func decodeTranscriptList() throws -> [CoreCLIInfo] {
        struct Line: Decodable {
            struct Message: Decodable {
                let result: CoreCLIsList?

                private enum Keys: String, CodingKey { case result }

                // Only the `clis.list` reply decodes as a list; the `initialize` reply and the errors read as nil.
                init(from decoder: Decoder) throws {
                    result = try? decoder.container(keyedBy: Keys.self).decode(CoreCLIsList.self, forKey: .result)
                }
            }
            let dir: String
            let json: Message
        }
        let text = try String(contentsOf: CoreTestData.directory.appendingPathComponent("rpc/clis_list.jsonl"), encoding: .utf8)
        let replies = try text.split(separator: "\n").map { try JSONDecoder().decode(Line.self, from: Data($0.utf8)) }
            .filter { $0.dir == "recv" }.compactMap(\.json.result)
        guard let first = replies.first else { throw CoreError("no clis.list reply", status: 500) }
        return first.clis
    }
}

/// Runs a suite's tests with `CLICatalogFixture.catalog` as the catalog: the suite's scope sets the task-local, and its tests run
/// in child tasks of that scope, which inherit it.
struct FixtureCLIs: SuiteTrait, TestScoping {
    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        try await CLICatalog.$scoped.withValue(CLICatalogFixture.catalog) { try await function() }
    }
}

extension Trait where Self == FixtureCLIs {
    static var fixtureCLIs: Self { Self() }
}
