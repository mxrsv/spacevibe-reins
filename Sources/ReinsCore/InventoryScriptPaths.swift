import Foundation

extension Inventory {
    private static let scriptExtensions: Set<String> = ["sh", "bash", "zsh", "js", "mjs", "cjs", "ts", "py", "rb"]
    // Quoted '/abs', quoted "/abs" without $, or a bare /abs after whitespace or at the start. Same pattern as core/inventory.mjs.
    private static let scriptPathPattern = try! NSRegularExpression(pattern: #"'(/[^']+)'|"(/[^"$]+)"|(?:^|\s)(/[^\s'";|&)]+)"#)

    /// Absolute script paths a hook command points at, in order of first appearance. A command is dead only when it names at
    /// least one script path and none of them exists any more. The command is never executed (S-R4).
    public static func scriptPaths(_ command: String) -> [String] {
        var found: [String] = []
        let whole = NSRange(command.startIndex..., in: command)
        for match in scriptPathPattern.matches(in: command, range: whole) {
            let range = [1, 2, 3].map { match.range(at: $0) }.first { $0.location != NSNotFound }
            guard let range, let swiftRange = Range(range, in: command) else { continue }
            let path = String(command[swiftRange])
            guard scriptExtensions.contains(where: { path.hasSuffix("." + $0) }), !found.contains(path) else { continue }
            found.append(path)
        }
        return found
    }
}
