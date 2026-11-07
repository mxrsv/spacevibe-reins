import Foundation

/// Price of one model in USD per million tokens (standard API-equivalent; not what a subscription costs).
public struct ModelPrice: Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheWrite: Double
    public var cacheWriteLong: Double
    public var cacheRead: Double
}

/// The estimate-only price table. It is a Swift literal, not a bundled JSON file, so ReinsCore needs no resource bundle.
/// A test compares it with core/internal/pricing/pricing.json (fetched 2026-10-24 from https://platform.claude.com/docs/en/about-claude/pricing
/// for Claude; the GPT rows follow the same file). Models that need tier information nobody observed are left out on purpose:
/// no price means no estimate (`nil`), never a guess.
public enum Pricing {
    public static let models: [String: ModelPrice] = [
        "claude-opus-5-5": ModelPrice(input: 4.0, output: 20.0, cacheWrite: 5.0, cacheWriteLong: 8.0, cacheRead: 0.2),
        "claude-sonnet-5-5": ModelPrice(input: 2.0, output: 10.0, cacheWrite: 2.5, cacheWriteLong: 4.0, cacheRead: 0.1),
        "claude-opus-4-6": ModelPrice(input: 5.0, output: 25.0, cacheWrite: 6.25, cacheWriteLong: 10.0, cacheRead: 0.5),
        "claude-sonnet-4-6": ModelPrice(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheWriteLong: 6.0, cacheRead: 0.3),
        "claude-haiku-4-5": ModelPrice(input: 1.0, output: 5.0, cacheWrite: 1.25, cacheWriteLong: 2.0, cacheRead: 0.1),
        "gpt-6-astra": ModelPrice(input: 10.0, output: 50.0, cacheWrite: 12.5, cacheWriteLong: 25.0, cacheRead: 1.0),
        "gpt-6.1-sol": ModelPrice(input: 2.0, output: 10.0, cacheWrite: 2.5, cacheWriteLong: 5.0, cacheRead: 0.1),
        "gpt-6-luna": ModelPrice(input: 0.1, output: 0.5, cacheWrite: 0.125, cacheWriteLong: 0.25, cacheRead: 0.01),
    ]

    /// The price for a model name as logged: exact match first, then without a trailing `[1m]`-style suffix and a `-YYYYMMDD` date.
    public static func price(for model: String, in table: [String: ModelPrice] = Pricing.models) -> ModelPrice? {
        if let exact = table[model] { return exact }
        return table[cleanName(model)]
    }

    static func cleanName(_ model: String) -> String {
        var name = model
        // /\[[^\]]*\]$/
        if name.hasSuffix("]"), let open = name.lastIndex(of: "["), !name[name.index(after: open)...].dropLast().contains("]") {
            name = String(name[..<open])
        }
        // /-\d{8}$/
        let tail = Array(name.utf8.suffix(9))
        if tail.count == 9, tail[0] == 0x2D, tail[1...].allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) { name = String(name.dropLast(9)) }
        return name
    }

    /// Token counts of one model, as the log folding sums them.
    struct Usage {
        var input = 0.0
        var output = 0.0
        var cacheWrite = 0.0
        var cacheWriteLong = 0.0
        var cacheRead = 0.0
    }

    enum Estimate: Equatable {
        case usd(Double)
        case note(String)
    }

    /// Models are summed in the order given (floating point addition is not associative, and the golden compares exact values).
    static func estimate(_ usage: [(model: String, usage: Usage)], table: [String: ModelPrice] = Pricing.models) -> Estimate {
        var usd = 0.0
        var any = false
        for (model, m) in usage {
            let tokens = m.input + m.output + m.cacheWrite + m.cacheRead
            if tokens == 0 { continue }
            guard let rate = price(for: model, in: table) else { return .note("No price for model \"\(model)\", so no estimate.") }
            let long = min(m.cacheWrite, m.cacheWriteLong)
            let sum = m.input * rate.input + m.output * rate.output + m.cacheRead * rate.cacheRead
                + (m.cacheWrite - long) * rate.cacheWrite + long * rate.cacheWriteLong
            usd += sum / 1_000_000
            any = true
        }
        return any ? .usd(usd) : .note("No token usage logged yet.")
    }
}
