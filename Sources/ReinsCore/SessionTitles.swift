import Foundation

/// Session titles and project names (core/session-titles.mjs). Pure helpers plus a read-only `.git` lookup; nothing here runs a command.
public enum SessionTitles {
    static let titleMax = 80

    /// True for text that is not a title: empty, a slash command, lifecycle or caveat text.
    public static func isJunk(_ text: String) -> Bool {
        let t = ActivityText.squash(text)
        if t.utf16.count < 2 || !t.unicodeScalars.contains(where: isLetterOrNumber) { return true }
        if isSlashCommand(t) { return true }
        if t.hasPrefix("<") { return true }
        for tag in ["<command-name>", "<local-command", "<system-reminder", "<task-notification"] where t.contains(tag) { return true }
        let lower = t.lowercased()
        if lower.hasPrefix("caveat:") || lower.hasPrefix("[request interrupted") || lower.hasPrefix("# agents.md instructions") { return true }
        return ["warmup", "untitled", "new session", "no title", "claude session", "codex session"].contains(lower)
    }

    private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    /// `/^\/[\w:-]+(\s|$)/`: "/clear", "/model opus". A path such as "/Users/me/x" is not a command.
    private static func isSlashCommand(_ t: String) -> Bool {
        guard t.hasPrefix("/") else { return false }
        var sawName = false
        for scalar in t.unicodeScalars.dropFirst() {
            let v = scalar.value
            let word = (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || v == 0x5F || v == 0x3A || v == 0x2D
            if word { sawName = true; continue }
            return sawName && ActivityText.isJSSpace(scalar)
        }
        return sawName
    }

    /// Single line, at most 80 UTF-16 units, ending in an ellipsis when cut.
    public static func clean(_ text: String) -> String {
        let t = ActivityText.squash(text)
        return t.utf16.count > titleMax ? ActivityText.prefix(t, titleMax - 1) + "…" : t
    }

    /// The first candidate that is not junk, else `YYYY-MM-DD · short id`. `startedAt` is epoch milliseconds.
    public static func pick(_ candidates: [String?], startedAt: Double?, id: String?) -> String {
        for candidate in candidates {
            if let candidate, !isJunk(candidate) { return clean(candidate) }
        }
        let day = startedAt.map { $0.isFinite ? ActivityText.isoDay($0) : "unknown date" } ?? "unknown date"
        return "\(day) · \(ActivityText.prefix(id ?? "", 8))"
    }
}

/// Caches `projectName` answers within one read.
final class ProjectNameMemo {
    var values: [String: String] = [:]
}

private let worktreeClaude = try! NSRegularExpression(pattern: #"^(.*)[\\/]\.claude[\\/]worktrees[\\/][^\\/]+(?:[\\/].*)?$"#)
private let worktreeCodex = try! NSRegularExpression(pattern: #"[\\/]\.codex[\\/]worktrees[\\/][^\\/]+[\\/]([^\\/]+)(?:[\\/].*)?$"#)
private let gitdirWorktree = try! NSRegularExpression(pattern: #"^(.*)[\\/]\.git[\\/]worktrees[\\/][^\\/]+$"#)
private let gitdirLine = try! NSRegularExpression(pattern: #"^gitdir:\s*(.+)$"#, options: [.anchorsMatchLines])

private func firstGroup(_ regex: NSRegularExpression, in text: String) -> String? {
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[r])
}

/// The main repo name when `cwd` (or a parent) is a linked worktree, whose `.git` is a pointer file.
/// A `.git` directory means a normal checkout: nil, so the caller keeps the folder name.
private func worktreeRepo(_ cwd: String, depth: Int = 12) -> String? {
    var dir = cwd
    let fm = FileManager.default
    for _ in 0..<depth {
        let git = (dir as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: git, isDirectory: &isDirectory) {
            if isDirectory.boolValue { return nil }
            let text = (try? String(contentsOfFile: git, encoding: .utf8)) ?? ""
            let gitdir = firstGroup(gitdirLine, in: text).map(ActivityText.trim)
            var main: String?
            if let gitdir, !gitdir.isEmpty {
                let absolute = gitdir.hasPrefix("/") ? gitdir : URL(fileURLWithPath: gitdir, relativeTo: URL(fileURLWithPath: dir, isDirectory: true)).standardizedFileURL.path
                main = firstGroup(gitdirWorktree, in: absolute)
            }
            if let main, !main.isEmpty { return ActivityText.basename(main) }
            return ActivityText.basename(dir)
        }
        let up = ActivityText.dirname(dir)
        if up == dir { return nil }
        dir = up
    }
    return nil
}

/// The repo name for a working directory; a git worktree slug is never returned.
/// Order: `hint` (the original cwd Claude records for a worktree), the `.claude/worktrees/<slug>` and
/// `.codex/worktrees/<id>/<repo>` layouts, the `.git` pointer file on disk, then the folder name.
func projectName(_ cwd: String?, hint: String? = nil, memo: ProjectNameMemo? = nil) -> String? {
    guard let cwd, !cwd.isEmpty else { return nil }
    let key = "\(cwd)\0\(hint ?? "")"
    if let cached = memo?.values[key] { return cached }
    var name: String?
    if let hint, !hint.isEmpty { name = projectName(hint, hint: nil, memo: memo) }
    if name == nil {
        if let claude = firstGroup(worktreeClaude, in: cwd), !claude.isEmpty {
            name = ActivityText.basename(claude)
        } else {
            name = firstGroup(worktreeCodex, in: cwd)
        }
    }
    if name == nil { name = worktreeRepo(cwd) }
    if name == nil {
        let base = ActivityText.basename(cwd)
        name = base.isEmpty ? cwd : base
    }
    memo?.values[key] = name
    return name
}

/// Public entry for callers (and tests) that name a project outside a read.
public func activityProjectName(cwd: String?, hint: String? = nil) -> String? {
    projectName(cwd, hint: hint)
}
