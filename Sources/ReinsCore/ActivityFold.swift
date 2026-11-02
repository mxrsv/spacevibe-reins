import Foundation

// Folds one session log (a Claude Code transcript or a Codex rollout) into a small state object, one line at a time.
// Port of core/activity-fold.mjs. Read-only: it parses recorded text and never runs a recorded command or hook (R4).
// Most lines are skipped by a byte search before any JSON parse; the search strings are the ones the Node code used, so
// both sides skip the same lines.

struct ActivityFailureEvent {
    var id: String
    var key: String
    var cmd: String
    var at: Double
    var exit: Int
    var reason: String
}

struct ActivityHookEvent {
    var id: String
    var event: String
    var command: String
    var at: Double
    var exit: Int?
    var reason: String
}

struct ActivityEditEvent {
    var id: String
    var path: String
    var at: Double
}

struct ActivityPendingCall {
    var name: String
    var target: String
    var at: Double
    var track: Bool
}

/// The mutable per-log state. A class on purpose: logs reach hundreds of MB and a copy per line is too slow.
final class ActivityLogState {
    let cli: ActivityCLI
    var invalid = 0
    var id: String?
    var cwd: String?
    var startedAt: Double?
    var parent = false
    var worktreeOriginal: String?
    var customTitle: String?
    var aiTitle: String?
    var firstPrompt: String?
    var model = "unknown"
    var metrics = OrderedMap<Pricing.Usage>()
    var claudeUsageSeen: [String: Pricing.Usage] = [:]
    var codexTotalsSeen = Set<String>()
    var cumulative: CodexTokens?
    /// Codex only: "busy" after task_started, "idle" after task_complete or turn_aborted.
    var status: String?
    var pending = OrderedMap<ActivityPendingCall>()
    var questions = Set<String>()
    var bash: [String: String] = [:]
    var editsPending: [String: (paths: [String], at: Double)] = [:]
    var failures: [ActivityFailureEvent] = []
    var hookFailures: [ActivityHookEvent] = []
    var passes: [String: [Double]] = [:]
    var edits: [ActivityEditEvent] = []
    var legacyEdits: [ActivityEditEvent] = []
    var sawFileChange = false

    init(cli: ActivityCLI) { self.cli = cli }

    struct CodexTokens {
        var input = 0.0
        var output = 0.0
        var cacheRead = 0.0
    }
}

// MARK: - JSON access with JavaScript semantics

private extension JSONValue {
    /// The member, or nil for a missing key or JSON null (what `??` treats as nullish).
    func field(_ key: String) -> JSONValue? {
        guard let v = self[key], v != .null else { return nil }
        return v
    }

    var number: Double? { numberText.flatMap { Double($0) } }

    /// JavaScript truthiness.
    var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let text): return Double(text).map { $0 != 0 && !$0.isNaN } ?? true
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    /// `Number.isInteger`
    var integer: Int? {
        guard let d = number, d.isFinite, d == d.rounded(), abs(d) < 9e15 else { return nil }
        return Int(d)
    }
}

private extension Optional where Wrapped == JSONValue {
    func field(_ key: String) -> JSONValue? { self?.field(key) }
    var string: String? { self?.stringValue }
    var truthy: Bool { self?.truthy ?? false }
}

private func count(_ v: JSONValue?) -> Double {
    if let d = v?.number, d.isFinite, d >= 0 { return d }
    return 0
}

private func atOf(_ r: JSONValue) -> Double {
    r.field("timestamp")?.stringValue.flatMap(ActivityText.parseTimestamp) ?? 0
}

// MARK: - Shared helpers

enum ActivityFold {
    static let preview = 160
    static let passesPerCommand = 50

    private static let exploreRE = try! NSRegularExpression(
        pattern: #"^(cat|ls|rg|grep|find|sed|head|tail|wc|echo|pwd|which|stat|file|du|diff|git\s+(status|log|diff|show|branch|rev-parse|ls-files|grep|check-ignore)|gh\s+\S+\s+(view|list)|test\s|\[)"#
    )
    private static let errorLineRE = try! NSRegularExpression(
        pattern: #"(\berror\b|\bfailed\b|\bfail\b|exception|cannot|could not|couldn't|not found|denied|panic|fatal|unexpected|undefined is|is not a function|✗|×)"#,
        options: [.caseInsensitive]
    )
    private static let zeroCountRE = try! NSRegularExpression(pattern: #"\b0 (failed|errors?)\b"#, options: [.caseInsensitive])
    private static let exitLineRE = try! NSRegularExpression(pattern: #"^Exit code \d+$"#)
    private static let exitCodeRE = try! NSRegularExpression(pattern: #"^Exit code (\d+)"#)
    private static let stripCdRE = try! NSRegularExpression(pattern: #"^cd\s+\S+\s*(&&|;)\s*"#)
    private static let patchFileRE = try! NSRegularExpression(pattern: #"\*\*\* (?:Update|Add|Delete) File: ([^\n\\"]+)"#)
    private static let editTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]

    static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// `s.replace(/\s+/g, ' ').trim().slice(0, n)` for a string; '' for anything else.
    static func previewText(_ value: String?, _ n: Int = preview) -> String {
        guard let value else { return "" }
        return ActivityText.prefix(ActivityText.squash(value), n)
    }

    private static func stripCd(_ cmd: String) -> String {
        let trimmed = ActivityText.trim(cmd)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let m = stripCdRE.firstMatch(in: trimmed, range: range), let r = Range(m.range, in: trimmed) else { return trimmed }
        return String(trimmed[r.upperBound...])
    }

    static func normalizeCommand(_ cmd: String) -> String {
        ActivityText.prefix(ActivityText.collapse(stripCd(cmd)), 400)
    }

    /// grep, ls and diff exit non-zero by design, so they are not failures.
    private static func isExploratory(_ cmd: String) -> Bool { matches(exploreRE, stripCd(cmd)) }

    /// The line a person would quote from a failure, not the runner's preamble.
    static func errorLine(_ output: String) -> String {
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = ActivityText.trim(String(raw))
            if line.isEmpty || matches(exitLineRE, line) { continue }
            if matches(errorLineRE, line), !matches(zeroCountRE, line) { return ActivityText.prefix(line, preview) }
        }
        return ""
    }

    /// Text of a tool result `content`: a string, or the text blocks of an array joined by newlines.
    static func textOf(_ content: JSONValue?) -> String {
        guard let content else { return "" }
        if let s = content.stringValue { return s }
        guard let items = content.arrayValue else { return "" }
        var parts: [String] = []
        for b in items {
            let text: String
            if let s = b.stringValue { text = s } else { text = b.field("text")?.stringValue ?? b.field("input_text")?.stringValue ?? "" }
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: "\n")
    }

    /// `(?:^|__|\.)(AskUserQuestion|request_user_input(?:_async)?)$`
    static func isQuestionTool(_ name: String?) -> Bool {
        guard let name else { return false }
        for tool in ["AskUserQuestion", "request_user_input", "request_user_input_async"] {
            if name == tool || name.hasSuffix("__" + tool) || name.hasSuffix("." + tool) { return true }
        }
        return false
    }

    // MARK: State updates

    private static func recordOutcome(_ st: ActivityLogState, id: String, cmd: String, at: Double, exit: Int, output: String) {
        let command = normalizeCommand(cmd)
        if command.isEmpty { return }
        let key = ActivityText.sha12(command)
        if exit == 0 {
            var list = st.passes[key] ?? []
            list.append(at)
            if list.count > passesPerCommand { list.removeFirst() }
            st.passes[key] = list
        } else if !isExploratory(cmd) {
            let line = errorLine(output)
            st.failures.append(ActivityFailureEvent(id: id, key: key, cmd: command, at: at, exit: exit, reason: line.isEmpty ? "Exit \(exit)" : line))
        }
    }

    private static func addPrompt(_ st: ActivityLogState, _ text: String) {
        let plain = ActivityText.trim(text)
        if SessionTitles.isJunk(plain) { return }
        st.pending.removeAll()
        st.questions.removeAll()
        if st.firstPrompt == nil { st.firstPrompt = SessionTitles.clean(plain) }
    }

    private static func addPending(_ st: ActivityLogState, id: String?, name: String?, target: String?, at: Double, track: Bool) {
        guard let id, !id.isEmpty else { return }
        st.pending[id] = ActivityPendingCall(name: previewText(name), target: previewText(target), at: at, track: track)
        if isQuestionTool(name) { st.questions.insert(id) }
    }

    private static func finishPending(_ st: ActivityLogState, id: String?, failed: Bool) {
        guard let id, !id.isEmpty else { return }
        let pending = st.pending[id]
        st.pending[id] = nil
        // request_user_input_async answers immediately; the wait ends at the next user message instead.
        if st.questions.contains(id), failed || !(pending?.name.hasSuffix("request_user_input_async") ?? false) { st.questions.remove(id) }
    }

    // MARK: Claude Code transcript

    private static func claudeToolResult(_ st: ActivityLogState, _ block: JSONValue, at: Double) {
        let id = block.field("tool_use_id")?.stringValue
        let failed = block.field("is_error")?.boolValue == true
        finishPending(st, id: id, failed: failed)
        guard let id else { return }
        if let cmd = st.bash[id] {
            st.bash[id] = nil
            let output = textOf(block["content"])
            var exit: Int? = 0
            if failed {
                exit = nil
                let range = NSRange(output.startIndex..., in: output)
                if let m = exitCodeRE.firstMatch(in: output, range: range), let r = Range(m.range(at: 1), in: output) { exit = Int(output[r]) }
            }
            if let exit { recordOutcome(st, id: id, cmd: cmd, at: at, exit: exit, output: output) }
        }
        if let edit = st.editsPending[id] {
            st.editsPending[id] = nil
            if !failed { for path in edit.paths { st.edits.append(ActivityEditEvent(id: "\(id):\(path)", path: path, at: edit.at)) } }
        }
    }

    private static func claudeHookFailure(_ st: ActivityLogState, _ r: JSONValue, _ a: JSONValue) {
        let blocking = a.field("type")?.stringValue == "hook_blocking_error"
        let command = blocking ? a.field("blockingError").field("command")?.stringValue : a.field("command")?.stringValue
        guard let command, let event = a.field("hookEvent")?.stringValue else { return }
        let raw: String?
        if blocking {
            raw = a.field("blockingError").field("blockingError")?.stringValue
        } else if let stderr = a.field("stderr"), stderr.truthy {
            raw = stderr.stringValue
        } else {
            raw = a.field("stdout")?.stringValue
        }
        let exit = a.field("exitCode")?.integer
        let id = r.field("uuid")?.stringValue ?? "\(a.field("toolUseID")?.stringValue ?? "undefined"):\(event):\(command)"
        let firstLine = (raw ?? "").split(separator: "\n", omittingEmptySubsequences: false).first { !ActivityText.trim(String($0)).isEmpty }.map(String.init) ?? ""
        let shown = previewText(firstLine)
        let reason = shown.isEmpty ? (exit == nil ? "Hook failed" : "Exit \(exit!)") : shown
        st.hookFailures.append(ActivityHookEvent(id: id, event: event, command: command, at: atOf(r), exit: exit, reason: reason))
    }

    private static func claudeAssistant(_ st: ActivityLogState, _ r: JSONValue) {
        let m = r.field("message")
        if let model = m.field("model")?.stringValue, model != "<synthetic>" { st.model = model }
        let at = atOf(r)
        if let u = m.field("usage"), u.truthy {
            // Streaming blocks repeat the message usage, so keep the maximum per message id.
            let values = Pricing.Usage(
                input: count(u["input_tokens"]), output: count(u["output_tokens"]), cacheWrite: count(u["cache_creation_input_tokens"]),
                cacheWriteLong: count(u.field("cache_creation").field("ephemeral_1h_input_tokens")), cacheRead: count(u["cache_read_input_tokens"])
            )
            let messageId = m.field("id")?.stringValue ?? r.field("uuid")?.stringValue ?? "undefined"
            let key = "\(st.model):\(messageId)"
            let prev = st.claudeUsageSeen[key] ?? Pricing.Usage()
            var metric = st.metrics[st.model] ?? Pricing.Usage()
            metric.input += max(0, values.input - prev.input)
            metric.output += max(0, values.output - prev.output)
            metric.cacheWrite += max(0, values.cacheWrite - prev.cacheWrite)
            metric.cacheWriteLong += max(0, values.cacheWriteLong - prev.cacheWriteLong)
            metric.cacheRead += max(0, values.cacheRead - prev.cacheRead)
            st.metrics[st.model] = metric
            st.claudeUsageSeen[key] = Pricing.Usage(
                input: max(values.input, prev.input), output: max(values.output, prev.output), cacheWrite: max(values.cacheWrite, prev.cacheWrite),
                cacheWriteLong: max(values.cacheWriteLong, prev.cacheWriteLong), cacheRead: max(values.cacheRead, prev.cacheRead)
            )
        }
        for b in m.field("content")?.arrayValue ?? [] {
            guard b.field("type")?.stringValue == "tool_use" else { continue }
            let input = b.field("input") ?? .object([])
            let name = b.field("name")?.stringValue
            let command = input.field("command")?.stringValue
            let isBash = name == "Bash" && command != nil
            let file = input.field("file_path") ?? input.field("notebook_path")
            let targetValue = input.field("file_path") ?? input.field("command") ?? input.field("description") ?? input.field("pattern")
            let isEdit = name.map(editTools.contains) ?? false
            let id = b.field("id")?.stringValue
            addPending(st, id: id, name: name, target: targetValue?.stringValue, at: at, track: isBash || isEdit || isQuestionTool(name))
            guard let id, !id.isEmpty else { continue }
            if isBash, let command { st.bash[id] = command }
            if isEdit, let path = file?.stringValue { st.editsPending[id] = ([path], at) }
        }
    }

    static func foldClaude(_ st: ActivityLogState, _ line: Data) {
        let resultLine = ActivityText.contains(line, "\"tool_result\"")
        if resultLine, !ActivityText.contains(line, "\"type\":\"assistant\"") {
            // Most result lines are big file reads nobody needs: skip them unless a tracked tool owns them.
            let ids = ActivityText.toolUseIds(in: line)
            if !ids.isEmpty, !ids.contains(where: { st.pending[$0]?.track == true }) {
                for id in ids { finishPending(st, id: id, failed: false) }
                return
            }
        }
        let attachment = ActivityText.contains(line, "\"type\":\"attachment\"")
        let wanted = resultLine || ActivityText.contains(line, "\"type\":\"user\"") || ActivityText.contains(line, "\"type\":\"assistant\"")
            || ActivityText.contains(line, "\"type\":\"ai-title\"") || ActivityText.contains(line, "\"type\":\"custom-title\"")
            || ActivityText.contains(line, "\"type\":\"worktree-state\"")
            || (attachment && (ActivityText.contains(line, "hook_non_blocking_error") || ActivityText.contains(line, "hook_blocking_error")))
        if !wanted { return }
        guard let doc = try? OrderedJSON(data: line), doc.root.objectValue != nil else { st.invalid += 1; return }
        let r = doc.root
        if let cwd = r.field("cwd")?.stringValue, !cwd.isEmpty, (st.cwd ?? "").isEmpty { st.cwd = cwd }
        if st.startedAt == nil || st.startedAt == 0 {
            let parsed = atOf(r)
            st.startedAt = parsed == 0 ? nil : parsed
        }
        switch r.field("type")?.stringValue {
        case "ai-title": if let t = r.field("aiTitle")?.stringValue { st.aiTitle = t }
        case "custom-title": if let t = r.field("customTitle")?.stringValue { st.customTitle = t }
        case "worktree-state": if let o = r.field("worktreeSession").field("originalCwd")?.stringValue { st.worktreeOriginal = o }
        case "attachment":
            if let a = r.field("attachment"), ["hook_non_blocking_error", "hook_blocking_error"].contains(a.field("type")?.stringValue ?? "") {
                claudeHookFailure(st, r, a)
            }
        case "assistant": claudeAssistant(st, r)
        case "user":
            let content = r.field("message").field("content")
            let at = atOf(r)
            var text = ""
            if let blocks = content?.arrayValue {
                for b in blocks {
                    let type = b.field("type")?.stringValue
                    if type == "tool_result" { claudeToolResult(st, b, at: at) } else if type == "text", let t = b.field("text")?.stringValue { text += t + "\n" }
                }
            } else if let t = content?.stringValue {
                text += t + "\n"
            }
            if !text.isEmpty, !r["isMeta"].truthy, !r["isCompactSummary"].truthy, !r["isSidechain"].truthy { addPrompt(st, text) }
        default: break
        }
    }

    // MARK: Codex rollout

    private static func codexTokens(_ u: JSONValue) -> ActivityLogState.CodexTokens {
        ActivityLogState.CodexTokens(
            input: count(u["input_tokens"]), output: count(u["output_tokens"]),
            cacheRead: count(u.field("cached_input_tokens") ?? u.field("cache_read_input_tokens"))
        )
    }

    private static func tokenText(_ d: Double) -> String { d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d) }

    private static func codexUsage(_ st: ActivityLogState, _ info: JSONValue?, model: String) {
        guard let u = info.field("total_token_usage"), u.truthy else { return }
        let total = codexTokens(u)
        // A rollout can interleave streams (an embedded reviewer has its own running total) and repeat a total, so a
        // total already seen adds nothing, and the turn's own usage is trusted over the difference between two totals.
        let seen = "\(tokenText(total.input)):\(tokenText(total.output)):\(tokenText(total.cacheRead))"
        if st.codexTotalsSeen.contains(seen) { return }
        st.codexTotalsSeen.insert(seen)
        let prior = st.cumulative ?? ActivityLogState.CodexTokens()
        let delta: ActivityLogState.CodexTokens
        if let last = info.field("last_token_usage"), last.truthy {
            delta = codexTokens(last)
        } else {
            delta = ActivityLogState.CodexTokens(
                input: total.input >= prior.input ? total.input - prior.input : total.input,
                output: total.output >= prior.output ? total.output - prior.output : total.output,
                cacheRead: total.cacheRead >= prior.cacheRead ? total.cacheRead - prior.cacheRead : total.cacheRead
            )
        }
        var metric = st.metrics[model] ?? Pricing.Usage()
        // Codex input includes cached tokens and output includes reasoning tokens.
        metric.input += max(0, delta.input - delta.cacheRead)
        metric.cacheRead += delta.cacheRead
        metric.output += delta.output
        st.metrics[model] = metric
        st.cumulative = total
    }

    private static func codexItem(_ st: ActivityLogState, _ item: JSONValue, at: Double) {
        switch item.field("type")?.stringValue {
        case "UserMessage":
            let blocks = (item.field("content")?.arrayValue ?? []).filter { $0.field("type")?.stringValue == "text" }
            let text = textOf(.array(blocks))
            if !text.isEmpty {
                st.questions.removeAll()
                if !SessionTitles.isJunk(text), st.firstPrompt == nil { st.firstPrompt = SessionTitles.clean(text) }
            }
        case "CommandExecution":
            let command = item.field("command")
            let cmd = command?.arrayValue != nil ? command?.arrayValue?.last?.stringValue : command?.stringValue
            if let cmd, let exit = item.field("exit_code")?.integer {
                let id = item.field("id")?.stringValue ?? "undefined"
                recordOutcome(st, id: id, cmd: cmd, at: at, exit: exit, output: item.field("aggregated_output")?.stringValue ?? "")
            }
        case "FileChange":
            st.sawFileChange = true
            if let status = item.field("status"), status.truthy {
                let text = status.stringValue ?? ""
                let lower = text.lowercased()
                if !lower.contains("complete"), !lower.contains("success") { return }
            }
            let id = item.field("id")?.stringValue ?? "undefined"
            for member in item.field("changes")?.objectValue ?? [] {
                st.edits.append(ActivityEditEvent(id: "\(id):\(member.key)", path: member.key, at: at))
            }
        default: break
        }
    }

    private static func codexResponse(_ st: ActivityLogState, _ p: JSONValue, at: Double) {
        let type = p.field("type")?.stringValue
        if type == "function_call" || type == "custom_tool_call" {
            let rawValue = p.field("arguments") ?? p.field("input")
            let raw = rawValue?.stringValue
            var target = ""
            if let raw, let parsed = try? OrderedJSON(text: raw) {
                let a = parsed.root
                if let command = a.field("command"), let items = command.arrayValue {
                    target = previewSource(items.last)
                } else {
                    target = previewSource(a.field("cmd") ?? a.field("command"))
                }
            }
            let name = p.field("name")?.stringValue
            addPending(st, id: p.field("call_id")?.stringValue, name: name, target: target, at: at, track: isQuestionTool(name))
            // Older rollouts record patches only as tool text; used when no FileChange item exists in the file.
            if let raw, raw.contains("*** ") {
                var n = 0
                let range = NSRange(raw.startIndex..., in: raw)
                for m in patchFileRE.matches(in: raw, range: range) {
                    guard let r = Range(m.range(at: 1), in: raw) else { continue }
                    let callId = p.field("call_id")?.stringValue ?? "undefined"
                    st.legacyEdits.append(ActivityEditEvent(id: "\(callId):\(n)", path: ActivityText.trim(String(raw[r])), at: at))
                    n += 1
                }
            }
        } else if type == "function_call_output" || type == "custom_tool_call_output" {
            finishPending(st, id: p.field("call_id")?.stringValue, failed: false)
        }
    }

    /// A target is shown through `preview()`, which only keeps strings.
    private static func previewSource(_ v: JSONValue?) -> String { v?.stringValue ?? "" }

    static func foldCodex(_ st: ActivityLogState, _ line: Data) {
        let wanted = ActivityText.contains(line, "\"type\":\"session_meta\"") || ActivityText.contains(line, "\"type\":\"turn_context\"")
            || (ActivityText.contains(line, "\"type\":\"event_msg\"")
                && (ActivityText.contains(line, "\"type\":\"task_started\"") || ActivityText.contains(line, "\"type\":\"task_complete\"")
                    || ActivityText.contains(line, "\"type\":\"turn_aborted\"") || ActivityText.contains(line, "\"type\":\"token_count\"")
                    || ActivityText.contains(line, "\"type\":\"item_completed\"") || ActivityText.contains(line, "\"type\":\"user_message\""))
                && (!ActivityText.contains(line, "\"type\":\"item_completed\"")
                    || ActivityText.contains(line, "\"type\":\"UserMessage\"") || ActivityText.contains(line, "\"type\":\"CommandExecution\"")
                    || ActivityText.contains(line, "\"type\":\"FileChange\"")))
            || (ActivityText.contains(line, "\"type\":\"response_item\"")
                && (ActivityText.contains(line, "\"type\":\"function_call") || ActivityText.contains(line, "\"type\":\"custom_tool_call")))
        if !wanted { return }
        guard let doc = try? OrderedJSON(data: line), doc.root.objectValue != nil else { st.invalid += 1; return }
        let r = doc.root
        let p = r.field("payload") ?? .object([])
        let at = atOf(r)
        switch r.field("type")?.stringValue {
        case "session_meta":
            if st.id == nil { st.id = p.field("id")?.stringValue ?? p.field("session_id")?.stringValue }
            if st.cwd == nil { st.cwd = p.field("cwd")?.stringValue }
            if st.startedAt == nil {
                let fromPayload = p.field("timestamp")?.stringValue.flatMap(ActivityText.parseTimestamp) ?? 0
                let value = fromPayload != 0 ? fromPayload : at
                st.startedAt = value != 0 ? value : nil
            }
            st.parent = p.field("parent_thread_id").truthy || p.field("source").field("subagent").truthy
        case "turn_context":
            if let model = p.field("model")?.stringValue { st.model = model }
            if st.cwd == nil { st.cwd = p.field("cwd")?.stringValue }
        case "event_msg":
            switch p.field("type")?.stringValue {
            case "task_started":
                st.status = "busy"
                st.questions.removeAll()
            case "task_complete", "turn_aborted":
                st.status = "idle"
                st.pending.removeAll()
                st.questions.removeAll()
            case "item_completed":
                if let item = p.field("item"), item.truthy { codexItem(st, item, at: at) }
            case "user_message":
                st.questions.removeAll()
                if let message = p.field("message")?.stringValue, !SessionTitles.isJunk(message), st.firstPrompt == nil {
                    st.firstPrompt = SessionTitles.clean(message)
                }
            case "token_count":
                codexUsage(st, p.field("info"), model: st.model)
            default: break
            }
        case "response_item":
            codexResponse(st, p, at: at)
        default: break
        }
    }

    /// Edits of one log state, preferring FileChange items over the older tool-text patches.
    static func editsOf(_ st: ActivityLogState) -> [ActivityEditEvent] {
        if st.cli != .codex || st.sawFileChange { return st.edits }
        let base = st.cwd ?? ""
        return st.legacyEdits.map { e in
            if e.path.hasPrefix("/") || base.isEmpty { return e }
            let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
            return ActivityEditEvent(id: e.id, path: "\(trimmed)/\(e.path)", at: e.at)
        }
    }

    static func fold(_ st: ActivityLogState, _ line: Data) {
        if st.cli == .claude { foldClaude(st, line) } else { foldCodex(st, line) }
    }

    /// Hook failures use the inventory hash: sha(event|command).
    static func hookHash(event: String, command: String) -> String { ActivityText.sha12("\(event)|\(command)") }
}
