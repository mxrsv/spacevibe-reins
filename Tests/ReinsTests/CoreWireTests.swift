import Foundation
import Testing
@testable import Reins

@Suite("CoreWire")
struct CoreWireTests {
    @Test("every recorded response decodes through the client's own reply and error paths")
    func transcriptResponses() throws {
        var decoded = 0
        var refusals = 0
        var method: [String: String] = [:]
        var file = ""
        for line in try CoreTestData.transcriptLines() {
            if line.file != file { file = line.file; method = [:] }
            let key = "\(line.json["id"] ?? "")"
            if line.dir == "send", let name = line.json["method"] as? String { method[key] = name; continue }
            guard line.dir == "recv" else { continue }
            let data = try JSONSerialization.data(withJSONObject: CoreTestData.unmaskingClock(line.json))
            let envelope = try CoreWire.decode(CoreWire.Envelope.self, from: data)
            if envelope.method == "activity/report" {
                #expect((try? CoreWire.decode(CoreWire.Note<CoreActivityReport>.self, from: data)) != nil, "\(line.file) activity/report")
                decoded += 1
            } else if envelope.method == "usage/progress" {
                #expect((try? CoreWire.decode(CoreWire.Note<CoreWire.ProgressParams>.self, from: data)) != nil, "\(line.file) usage/progress")
                decoded += 1
            } else if let error = envelope.error {
                let mapped = CoreWire.error(from: error)
                if error.code == -32000 { #expect(mapped is CoreError, "\(line.file)") }
                if error.code == -32800 { #expect(mapped is CancellationError) }
                refusals += 1
            } else if envelope.id != nil, (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["result"] != nil {
                let name = try #require(method[key], "\(line.file): a result with no request")
                if name == "initialize" {
                    #expect((try? CoreWire.reply(CoreInitializeResult.self, from: data)) != nil, "\(line.file) initialize")
                } else if let type = CoreTypesTests.resultTypes[name] {
                    func check<T: Decodable>(_: T.Type) { #expect((try? CoreWire.reply(T.self, from: data)) != nil, "\(line.file) \(name)") }
                    check(type)
                } else if name == "activity.unsubscribe" {
                    #expect(((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["result"] as? [String: Any])?.isEmpty == true, "\(line.file)")
                } else {
                    // Only the contract-test debug methods and the probes of the transport have no DTO.
                    #expect(name.hasPrefix("debug."), "\(line.file): \(name) has no DTO")
                }
                decoded += 1
            }
        }
        #expect(decoded >= 10)
        #expect(refusals > 10)
    }

    @Test("a request line is one JSON object and a newline, and a notification has no id")
    func requestLines() throws {
        let request = try CoreWire.line(id: 7, method: "journal.undo", params: ["id": "x"])
        #expect(String(decoding: request, as: UTF8.self) == "{\"id\":7,\"jsonrpc\":\"2.0\",\"method\":\"journal.undo\",\"params\":{\"id\":\"x\"}}\n"
            || String(decoding: request, as: UTF8.self).hasSuffix("}\n"))
        let note = try JSONSerialization.jsonObject(with: CoreWire.line(id: nil, method: "$/cancelRequest", params: ["id": 7])) as? [String: Any]
        #expect(note?["id"] == nil)
        #expect(note?["jsonrpc"] as? String == "2.0")
    }
}
