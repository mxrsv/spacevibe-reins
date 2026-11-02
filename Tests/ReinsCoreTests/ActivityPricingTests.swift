import Foundation
import Testing
@testable import ReinsCore

@Suite("Activity pricing")
struct ActivityPricingTests {
    @Test("the Swift price table equals core/pricing.json")
    func tableMatchesNodeJSON() throws {
        let file = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("core/pricing.json")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let models = try #require(root["models"] as? [String: [String: Any]])
        #expect(Set(models.keys) == Set(Pricing.models.keys))
        for (name, row) in models {
            func rate(_ key: String) -> Double? { (row[key] as? NSNumber)?.doubleValue }
            let price = try #require(Pricing.models[name], "\(name) is missing from Pricing.swift")
            #expect(rate("input") == price.input, "\(name) input")
            #expect(rate("output") == price.output, "\(name) output")
            #expect(rate("cacheWrite") == price.cacheWrite, "\(name) cacheWrite")
            #expect(rate("cacheWriteLong") == price.cacheWriteLong, "\(name) cacheWriteLong")
            #expect(rate("cacheRead") == price.cacheRead, "\(name) cacheRead")
        }
    }

    @Test("estimate sums per model and says why when it cannot")
    func estimates() {
        var usage = Pricing.Usage()
        usage.input = 1_000_000
        #expect(Pricing.estimate([("claude-sonnet-4-6[1m]", usage)]) == .usd(3))
        #expect(Pricing.estimate([("claude-mystery-9", usage)]) == .note("No price for model \"claude-mystery-9\", so no estimate."))
        #expect(Pricing.estimate([("claude-sonnet-4-6", Pricing.Usage())]) == .note("No token usage logged yet."))
    }
}
