import Foundation

/// What one log file yields, and the only thing the cache keeps of it: names, days, hook hashes and durations. Never log text.
struct FileRecord: Codable, Equatable, Sendable {
    /// Bare name -> days (`YYYY-MM-DD`) on which it appeared in this file.
    var skill: [String: [String]] = [:]
    var agent: [String: [String]] = [:]
    var hook: [String: HookTotals] = [:]
}

/// Per-line parsing of Claude and Codex session logs. Ported from Node usage (git b58269d); the cheap byte checks come first so most
/// lines are never turned into a String.
enum UsageScan {
    private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
    // `\w` in JavaScript is ASCII only; ICU's is Unicode, so the classes are spelled out.
    private static let timestamp = regex(#""timestamp":"([0-9]{4}-[0-9]{2}-[0-9]{2})T"#)
    private static let skillTool = regex(#""name":"Skill","input":\{"skill":"([^"]+)""#)
    private static let slash = regex(#"<command-name>/([A-Za-z0-9_:-]+)</command-name>"#)
    private static let subagent = regex(#""subagent_type":"([^"]+)""#)
    private static let codexSkill = regex(#"skills/([A-Za-z0-9_-]+)/SKILL\.md"#)
    private static let codexAgent = regex(#"\\?"agent_type\\?":\s*\\?"([A-Za-z0-9_-]+)"#)
    private static let codexCall = regex(#""type":"(function_call|custom_tool_call)"|"CommandExecution""#)

    private static let needleTimestamp = Data(#""timestamp":""#.utf8)
    private static let needleSkill = Data(#""name":"Skill""#.utf8)
    private static let needleCommandName = Data("<command-name>".utf8)
    private static let needleUserType = Data(#""type":"user""#.utf8)
    private static let needleSubagent = Data(#""subagent_type":""#.utf8)
    private static let needleAttachment = Data(#""attachment""#.utf8)
    private static let needleHook = Data(#""hook"#.utf8)
    private static let needleSkillMd = Data("SKILL.md".utf8)
    private static let needleAgentType = Data("agent_type".utf8)

    private static func has(_ line: Data, _ needle: Data) -> Bool { line.range(of: needle) != nil }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int = 1, in text: String) -> String? {
        Range(match.range(at: index), in: text).map { String(text[$0]) }
    }

    /// The day of the first `"timestamp":"YYYY-MM-DD` in the line, or nil.
    static func day(of line: Data) -> String? {
        guard has(line, needleTimestamp) else { return nil }
        return day(of: String(decoding: line, as: UTF8.self))
    }

    private static func day(of text: String) -> String? {
        timestamp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { group($0, in: text) }
    }

    /// `YYYY-MM-DD` of a time in UTC, as `toISOString().slice(0, 10)`.
    static func isoDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    private static func note(_ group: inout [String: [String]], _ name: String, _ day: String?) {
        var days = group[name] ?? []
        if let day, !days.contains(day) { days.append(day) }
        group[name] = days
    }

    static func claudeLine(_ line: Data, into rec: inout FileRecord, fallbackDay: String) {
        let hasSkill = has(line, needleSkill)
        let hasSlash = has(line, needleCommandName) && has(line, needleUserType)
        let hasAgent = has(line, needleSubagent)
        let hasHook = has(line, needleAttachment) && has(line, needleHook)
        guard hasSkill || hasSlash || hasAgent || hasHook else { return }
        let text = String(decoding: line, as: UTF8.self)
        let seen = day(of: text) ?? fallbackDay
        if hasSkill { for m in matches(skillTool, in: text) { if let name = group(m, in: text) { note(&rec.skill, Inventory.bare(name), seen) } } }
        if hasSlash { for m in matches(slash, in: text) { if let name = group(m, in: text) { note(&rec.skill, Inventory.bare(name), seen) } } }
        if hasAgent { for m in matches(subagent, in: text) { if let name = group(m, in: text) { note(&rec.agent, Inventory.bare(name), seen) } } }
        if hasHook { hookRecord(text, into: &rec, day: seen) }
    }

    /// A `hook_*` attachment. `hook_blocking_error` nests the command under `blockingError`; the other types carry it at the top level.
    private static func hookRecord(_ text: String, into rec: inout FileRecord, day: String) {
        guard let doc = try? OrderedJSON(text: text), let attachment = doc.root["attachment"], attachment.objectValue != nil,
              let type = attachment["type"]?.stringValue, type.hasPrefix("hook_") else { return }
        guard let command = attachment["command"]?.stringValue ?? attachment["blockingError"]?["command"]?.stringValue else { return }
        let key = Inventory.hookHash(event: jsString(attachment["hookEvent"]), command: command)
        var h = rec.hook[key] ?? HookTotals()
        h.runs += 1
        if let ms = finite(attachment["durationMs"]) { h.ms += ms; h.timed += 1 }
        if type.contains("error") || (finite(attachment["exitCode"]).map { $0 != 0 } ?? false) { h.errors += 1 }
        if h.last == nil || day > h.last! { h.last = day }
        rec.hook[key] = h
    }

    static func codexLine(_ line: Data, into rec: inout FileRecord, fallbackDay: String) {
        let hasSkill = has(line, needleSkillMd)
        let hasAgent = has(line, needleAgentType)
        guard hasSkill || hasAgent else { return }
        let text = String(decoding: line, as: UTF8.self)
        guard codexCall.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { return }
        let seen = day(of: text) ?? fallbackDay
        if hasSkill { for m in matches(codexSkill, in: text) { if let name = group(m, in: text) { note(&rec.skill, name, seen) } } }
        if hasAgent { for m in matches(codexAgent, in: text) { if let name = group(m, in: text) { note(&rec.agent, name, seen) } } }
    }

    /// `Number.isFinite`: a JSON number only (not a boolean or a string).
    private static func finite(_ value: JSONValue?) -> Double? {
        guard let text = value?.numberText, let number = Double(text), number.isFinite else { return nil }
        return number
    }

    /// `${value}` of a JSON value, for the hook identity (`undefined` when the field is missing).
    private static func jsString(_ value: JSONValue?) -> String {
        switch value {
        case nil: return "undefined"
        case .some(.null): return "null"
        case .some(.string(let s)): return s
        case .some(.bool(let b)): return b ? "true" : "false"
        case .some(.number(let n)): return n
        case .some: return "[object Object]"
        }
    }
}
