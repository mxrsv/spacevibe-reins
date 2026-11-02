import Foundation

/// How Codex's permissions are configured. Codex has two models that must not be mixed: the legacy `sandbox_mode` plus
/// `[sandbox_workspace_write]`, or `default_permissions` with `[permissions.<name>]` profiles.
public enum CodexPermissionModel: String, Sendable {
    case legacy, profiles, both
}

public enum CodexApprovalPolicy: Equatable, Sendable {
    /// `on-request`, `never`, ...
    case mode(String)
    /// `[approval_policy.granular]`: one switch per kind of approval. Only boolean values are kept.
    case granular([JSONMember])
}

public struct CodexSandboxWorkspaceWrite: Equatable, Sendable {
    public let networkAccess: Bool?
    public let writableRoots: [String]
}

/// A `[permissions.<name>]` profile, counts only: no path, no glob and no value is returned.
public struct CodexProfile: Equatable, Sendable {
    public let name: String
    public let filesystemEntries: Int
    public let networkEntries: Int
    /// Scalar keys of `[permissions.<name>.network]` (booleans, strings, numbers), such as `enabled = true`.
    public let networkFlags: [JSONMember]
}

public struct CodexProject: Equatable, Sendable {
    public let path: String
    public let trustLevel: String?
}

/// Counts of `prefix_rule(...)` per decision across `~/.codex/rules/*.rules`. The patterns themselves are never returned.
public struct CodexRulesSummary: Equatable, Sendable {
    public var files = 0
    public var allow = 0
    public var prompt = 0
    public var forbidden = 0
    public var other = 0
}

/// The permission keys of Codex `config.toml`, read-only. Only the keys named here are read; nothing under
/// `[mcp_servers.*]`, `[shell_environment_policy]` or any env table is looked at, and no auth file is opened.
public struct CodexPermissions: Equatable, Sendable {
    /// False when there is no `config.toml`.
    public var present = false
    public var model = CodexPermissionModel.legacy
    /// `sandbox_mode = "danger-full-access"`: Codex runs without a sandbox.
    public var unrestricted = false
    public var warnings: [String] = []
    public var approvalPolicy: CodexApprovalPolicy?
    public var sandboxMode: String?
    public var sandboxWorkspaceWrite: CodexSandboxWorkspaceWrite?
    public var defaultPermissions: String?
    public var approvalsReviewer: String?
    public var profiles: [CodexProfile] = []
    public var projects: [CodexProject] = []
    public var rules = CodexRulesSummary()

    /// Same fields as `readCodexPermissions` in core/rules.mjs, minus the file path.
    public static func read(roots: Roots) -> CodexPermissions {
        var out = CodexPermissions()
        out.rules = summarizeRules(roots.codex.root.appendingPathComponent("rules", isDirectory: true))
        if let data = InventoryFileIO.readData(roots.codex.root.appendingPathComponent("config.toml"), maxBytes: InventoryFileIO.maxJSONBytes) {
            out.present = true
            out.fill(from: TOMLReader.read(String(decoding: data, as: UTF8.self)))
        }
        let hasProfiles = out.defaultPermissions != nil
        let hasLegacy = out.sandboxMode != nil
        out.model = hasProfiles && hasLegacy ? .both : hasProfiles ? .profiles : .legacy
        if out.model == .both { out.warnings.append("Both default_permissions and sandbox_mode are set. Codex expects only one of them.") }
        out.unrestricted = out.sandboxMode == "danger-full-access"
        return out
    }

    // MARK: config.toml

    private mutating func fill(from document: TOMLDocument) {
        var profileOrder: [String] = []
        var profileData: [String: (fs: Int, net: Int, flags: [JSONMember])] = [:]
        var projectOrder: [String] = []
        var projectTrust: [String: String?] = [:]
        var workspaceNetwork: TOMLValue?
        var workspaceRoots: TOMLValue?
        var workspaceSeen = false
        var granular: [JSONMember] = []
        var inlinePolicy: CodexApprovalPolicy?

        func setProject(_ path: String, _ trust: String?) {
            if projectTrust[path] == nil { projectOrder.append(path) }
            projectTrust[path] = .some(trust)
        }

        // Entries under `[[array]]` tables are ignored, as in the Node reader.
        for entry in document.entries where !entry.inArrayTable {
            let table = entry.table
            let key = entry.key
            if table.isEmpty, ["approval_policy", "sandbox_mode", "default_permissions", "approvals_reviewer"].contains(key) {
                switch key {
                case "approval_policy":
                    if let text = entry.value?.stringValue { inlinePolicy = .mode(text) }
                    else if let inline = entry.value?["granular"]?.tableValue { inlinePolicy = .granular(Self.booleans(inline)) }
                    else { inlinePolicy = nil }
                case "sandbox_mode": sandboxMode = entry.value?.stringValue
                case "default_permissions": defaultPermissions = entry.value?.stringValue
                default: approvalsReviewer = entry.value?.stringValue
                }
            } else if table.isEmpty, key == "sandbox_workspace_write" {
                if let pairs = entry.value?.tableValue {
                    for pair in pairs {
                        workspaceSeen = true
                        if pair.key == "network_access" { workspaceNetwork = pair.value }
                        if pair.key == "writable_roots" { workspaceRoots = pair.value }
                    }
                }
            } else if table == ["sandbox_workspace_write"], key == "network_access" || key == "writable_roots" {
                workspaceSeen = true
                if key == "network_access" { workspaceNetwork = entry.value } else { workspaceRoots = entry.value }
            } else if table == ["approval_policy", "granular"] {
                if let flag = entry.value?.boolValue { granular.removeAll { $0.key == key }; granular.append(JSONMember(key, .bool(flag))) }
            } else if table.count >= 2, table[0] == "permissions" {
                let name = table[1]
                if profileData[name] == nil { profileOrder.append(name); profileData[name] = (0, 0, []) }
                if table.count > 2, table[2] == "filesystem" {
                    profileData[name]!.fs += 1
                } else if table.count > 2, table[2] == "network" {
                    profileData[name]!.net += 1
                    if let flag = Self.scalar(entry.value), Self.isFlagKey(key) {
                        profileData[name]!.flags.removeAll { $0.key == key }
                        profileData[name]!.flags.append(JSONMember(key, flag))
                    }
                }
            } else if table.count == 2, table[0] == "projects", key == "trust_level" {
                setProject(table[1], entry.value?.stringValue)
            } else if table == ["projects"], entry.keyPath.count == 1, let trust = entry.value?["trust_level"]?.stringValue {
                setProject(key, trust)
            }
        }

        // `[approval_policy.granular]` replaces an unset or inline-table policy, never a plain string such as "never".
        if !granular.isEmpty {
            if case .mode = inlinePolicy {} else { inlinePolicy = .granular(granular) }
        }
        approvalPolicy = inlinePolicy
        profiles = profileOrder.map { name in
            let data = profileData[name]!
            return CodexProfile(name: name, filesystemEntries: data.fs, networkEntries: data.net, networkFlags: data.flags)
        }
        projects = projectOrder.map { CodexProject(path: $0, trustLevel: projectTrust[$0] ?? nil) }
        if workspaceSeen {
            sandboxWorkspaceWrite = CodexSandboxWorkspaceWrite(networkAccess: workspaceNetwork?.boolValue, writableRoots: workspaceRoots?.strings ?? [])
        }
    }

    private static func booleans(_ pairs: [TOMLPair]) -> [JSONMember] {
        pairs.compactMap { pair in pair.value.boolValue.map { JSONMember(pair.key, .bool($0)) } }
    }

    private static func isFlagKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy { ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") }
    }

    private static func scalar(_ value: TOMLValue?) -> JSONValue? {
        switch value {
        case .bool(let b): return .bool(b)
        case .string(let s), .raw(let s): return .string(s)
        case .integer(let n): return .number(String(n))
        case .float(let d): return .number(String(d))
        default: return nil
        }
    }

    // MARK: rules/*.rules

    private static let ruleStart = try! NSRegularExpression(pattern: "\(Rules.boundary)prefix_rule\(Rules.space)*\\(")
    private static let decision = try! NSRegularExpression(pattern: #"decision\#(Rules.space)*=\#(Rules.space)*["']([A-Za-z0-9_]+)["']"#)

    private static func summarizeRules(_ folder: URL) -> CodexRulesSummary {
        var out = CodexRulesSummary()
        for name in InventoryFileIO.list(folder) where name.hasSuffix(".rules") {
            guard let text = InventoryFileIO.readText(folder.appendingPathComponent(name)) else { continue }
            out.files += 1
            // Whole-line comments are dropped; a `#` after code is left alone, as in Node.
            let code = text.components(separatedBy: CharacterSet(charactersIn: "\n"))
                .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
                .filter { !Rules.jsTrimStart($0).hasPrefix("#") }
                .joined(separator: "\n")
            let whole = NSRange(code.startIndex..., in: code)
            let starts = ruleStart.matches(in: code, range: whole)
            for (index, match) in starts.enumerated() {
                let end = index + 1 < starts.count ? starts[index + 1].range.location : whole.length
                let chunk = NSRange(location: match.range.upperBound, length: end - match.range.upperBound)
                var verdict = "allow"
                if let found = decision.firstMatch(in: code, range: chunk), let range = Range(found.range(at: 1), in: code) { verdict = String(code[range]) }
                switch verdict {
                case "allow": out.allow += 1
                case "prompt": out.prompt += 1
                case "forbidden": out.forbidden += 1
                default: out.other += 1
                }
            }
        }
        return out
    }
}
