import Foundation

// Token counting of one log, shared by Activity (the cost of a live session) and the token ledger, so both read a log
// into the same numbers. Port of the usage part of core/activity-fold.mjs; the Activity goldens guard it.

/// A token count from a log: a finite number at or above 0, else 0.
func tokenCount(_ v: JSONValue?) -> Double {
    if let d = v?.number, d.isFinite, d >= 0 { return d }
    return 0
}

extension Pricing.Usage {
    mutating func add(_ other: Pricing.Usage) {
        input += other.input
        output += other.output
        cacheWrite += other.cacheWrite
        cacheWriteLong += other.cacheWriteLong
        cacheRead += other.cacheRead
    }
}

/// Claude Code: streaming blocks repeat a message's usage, so each model and message id counts its largest values once.
struct ClaudeUsageCounter {
    private var seen: [String: Pricing.Usage] = [:]

    /// What `usage` (a `message.usage` object) adds for `key` (`model:messageId`): its growth over the largest values that
    /// key already counted, never below 0.
    mutating func add(_ u: JSONValue, key: String) -> Pricing.Usage {
        let values = Pricing.Usage(
            input: tokenCount(u["input_tokens"]), output: tokenCount(u["output_tokens"]), cacheWrite: tokenCount(u["cache_creation_input_tokens"]),
            cacheWriteLong: tokenCount(u.field("cache_creation").field("ephemeral_1h_input_tokens")), cacheRead: tokenCount(u["cache_read_input_tokens"])
        )
        let prev = seen[key] ?? Pricing.Usage()
        seen[key] = Pricing.Usage(
            input: max(values.input, prev.input), output: max(values.output, prev.output), cacheWrite: max(values.cacheWrite, prev.cacheWrite),
            cacheWriteLong: max(values.cacheWriteLong, prev.cacheWriteLong), cacheRead: max(values.cacheRead, prev.cacheRead)
        )
        return Pricing.Usage(
            input: max(0, values.input - prev.input), output: max(0, values.output - prev.output), cacheWrite: max(0, values.cacheWrite - prev.cacheWrite),
            cacheWriteLong: max(0, values.cacheWriteLong - prev.cacheWriteLong), cacheRead: max(0, values.cacheRead - prev.cacheRead)
        )
    }
}

/// Codex: a rollout can interleave streams (an embedded reviewer has its own running total) and repeat a total, so a total
/// already seen adds nothing, and the turn's own usage is trusted over the difference between two totals.
struct CodexUsageCounter {
    private struct Totals {
        var input = 0.0
        var output = 0.0
        var cacheRead = 0.0
    }

    private var seen = Set<String>()
    private var cumulative: Totals?

    private static func totals(_ u: JSONValue) -> Totals {
        Totals(input: tokenCount(u["input_tokens"]), output: tokenCount(u["output_tokens"]),
               cacheRead: tokenCount(u.field("cached_input_tokens") ?? u.field("cache_read_input_tokens")))
    }

    private static func text(_ d: Double) -> String { d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d) }

    /// What one `token_count` event's `info` adds, or nil when it adds nothing (no total, or a total already seen).
    /// Codex logs input with cached tokens included and output with reasoning included, so the cached part is moved out
    /// of input into cache reads: input means uncached input for both CLIs.
    mutating func add(_ info: JSONValue?) -> Pricing.Usage? {
        guard let u = info.field("total_token_usage"), u.truthy else { return nil }
        let total = Self.totals(u)
        let key = "\(Self.text(total.input)):\(Self.text(total.output)):\(Self.text(total.cacheRead))"
        if seen.contains(key) { return nil }
        seen.insert(key)
        let prior = cumulative ?? Totals()
        let delta: Totals
        if let last = info.field("last_token_usage"), last.truthy {
            delta = Self.totals(last)
        } else {
            delta = Totals(
                input: total.input >= prior.input ? total.input - prior.input : total.input,
                output: total.output >= prior.output ? total.output - prior.output : total.output,
                cacheRead: total.cacheRead >= prior.cacheRead ? total.cacheRead - prior.cacheRead : total.cacheRead
            )
        }
        cumulative = total
        return Pricing.Usage(input: max(0, delta.input - delta.cacheRead), output: delta.output, cacheRead: delta.cacheRead)
    }
}
