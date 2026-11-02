import Foundation

extension UsageScan {
    /// Folds the per-file records into totals, session counts and the log window of each CLI.
    static func aggregate(_ files: [String: CachedFile], fileCount: Int) -> UsageResult {
        struct Names { var sessions = Set<String>(); var days = Set<String>() }
        struct Bucket {
            var skill: [String: Names] = [:]
            var agent: [String: Names] = [:]
            var hook: [String: HookTotals] = [:]
        }
        var buckets: [InventoryCLI: Bucket] = [.claude: Bucket(), .codex: Bucket()]
        var sessions: [InventoryCLI: Set<String>] = [.claude: [], .codex: []]
        var windows: [InventoryCLI: LogWindow] = [.claude: LogWindow(), .codex: LogWindow()]

        for file in files.values {
            let cli = file.cli
            sessions[cli, default: []].insert(file.session)
            var window = windows[cli] ?? LogWindow()
            window.files += 1
            if let first = file.first, window.oldest == nil || first < window.oldest! { window.oldest = first }
            if window.newest == nil || file.mtimeMs > window.newest! { window.newest = file.mtimeMs }
            windows[cli] = window

            var bucket = buckets[cli] ?? Bucket()
            for (name, days) in file.rec.skill {
                bucket.skill[name, default: Names()].sessions.insert(file.session)
                bucket.skill[name]?.days.formUnion(days)
            }
            for (name, days) in file.rec.agent {
                bucket.agent[name, default: Names()].sessions.insert(file.session)
                bucket.agent[name]?.days.formUnion(days)
            }
            for (key, h) in file.rec.hook {
                var u = bucket.hook[key] ?? HookTotals()
                u.runs += h.runs; u.ms += h.ms; u.timed += h.timed; u.errors += h.errors
                if let last = h.last, u.last == nil || last > u.last! { u.last = last }
                bucket.hook[key] = u
            }
            buckets[cli] = bucket
        }

        func totals(_ cli: InventoryCLI) -> CLIUsageTotals {
            let bucket = buckets[cli] ?? Bucket()
            func names(_ source: [String: Names]) -> [String: NameUsage] {
                source.mapValues { n in
                    let days = n.days.sorted()
                    return NameUsage(sessions: n.sessions.count, days: days, last: days.last)
                }
            }
            return CLIUsageTotals(skill: names(bucket.skill), agent: names(bucket.agent), hook: bucket.hook)
        }
        return UsageResult(
            totals: UsageTotals(claude: totals(.claude), codex: totals(.codex)),
            sessions: UsageSessions(claude: sessions[.claude]?.count ?? 0, codex: sessions[.codex]?.count ?? 0),
            windows: UsageWindows(claude: windows[.claude] ?? LogWindow(), codex: windows[.codex] ?? LogWindow()),
            files: fileCount
        )
    }
}
