// Runs the patterns of ActivityFold.swift and SessionTitles.swift (copied verbatim) over a corpus. See corpus.py.
import Foundation

func re(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: o) }
let explore = re(#"^(cat|ls|rg|grep|find|sed|head|tail|wc|echo|pwd|which|stat|file|du|diff|git\s+(status|log|diff|show|branch|rev-parse|ls-files|grep|check-ignore)|gh\s+\S+\s+(view|list)|test\s|\[)"#)
let errorLine = re(#"(\berror\b|\bfailed\b|\bfail\b|exception|cannot|could not|couldn't|not found|denied|panic|fatal|unexpected|undefined is|is not a function|✗|×)"#, [.caseInsensitive])
let zeroCount = re(#"\b0 (failed|errors?)\b"#, [.caseInsensitive])
let exitLine = re(#"^Exit code \d+$"#)
let exitCode = re(#"^Exit code (\d+)"#)
let stripCd = re(#"^cd\s+\S+\s*(&&|;)\s*"#)
let patchFile = re(#"\*\*\* (?:Update|Add|Delete) File: ([^\n\\"]+)"#)
let wtClaude = re(#"^(.*)[\\/]\.claude[\\/]worktrees[\\/][^\\/]+(?:[\\/].*)?$"#)
let wtCodex = re(#"[\\/]\.codex[\\/]worktrees[\\/][^\\/]+[\\/]([^\\/]+)(?:[\\/].*)?$"#)
let gitdirWt = re(#"^(.*)[\\/]\.git[\\/]worktrees[\\/][^\\/]+$"#)
let gitdirLine = re(#"^gitdir:\s*(.+)$"#, [.anchorsMatchLines])

func first(_ r: NSRegularExpression, _ t: String) -> NSTextCheckingResult? { r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) }
func group(_ r: NSRegularExpression, _ t: String, _ i: Int) -> Any {
    guard let m = first(r, t), let rg = Range(m.range(at: i), in: t) else { return NSNull() }
    return String(t[rg])
}

let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let cases = try! JSONSerialization.jsonObject(with: data) as! [[String: String]]
var out: [[String: Any]] = []
for c in cases {
    let name = c["re"]!, t = c["input"]!
    var r: Any
    switch name {
    case "explore": r = first(explore, t) != nil
    case "errorLine": r = first(errorLine, t) != nil
    case "zeroCount": r = first(zeroCount, t) != nil
    case "exitLine": r = first(exitLine, t) != nil
    case "exitCode": r = group(exitCode, t, 1)
    case "stripCd":
        if let m = first(stripCd, t), let rg = Range(m.range, in: t) { r = String(t[rg.upperBound...]) } else { r = NSNull() }
    case "patchFile":
        var list: [String] = []
        for m in patchFile.matches(in: t, range: NSRange(t.startIndex..., in: t)) { if let rg = Range(m.range(at: 1), in: t) { list.append(String(t[rg])) } }
        r = list
    case "wtClaude": r = group(wtClaude, t, 1)
    case "wtCodex": r = group(wtCodex, t, 1)
    case "gitdirWt": r = group(gitdirWt, t, 1)
    case "gitdirLine": r = group(gitdirLine, t, 1)
    case "split": r = t.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    default: r = "?"
    }
    out.append(["re": name, "input": t, "out": r])
}
let o = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .withoutEscapingSlashes])
try! o.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
