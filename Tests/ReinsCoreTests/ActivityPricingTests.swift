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

    @Test("a model priced by prompt length, or not confirmed on its vendor's page, has no price on purpose")
    func unpricedOnPurpose() {
        for model in ["claude-haiku-5-5", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.5"] { #expect(Pricing.price(for: model) == nil, "\(model)") }
        #expect(Pricing.price(for: "claude-fable-5-1")?.cacheRead == 0.25)
        #expect(Pricing.price(for: "claude-opus-5")?.input == 5)
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
