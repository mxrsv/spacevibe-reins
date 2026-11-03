import ReinsCore
import SwiftUI

/// The real Codex settings, read only: approval policy, sandbox, network, profile, the count of rules per decision and project trust.
struct RulesCodexGroup: View {
    let snapshot: RulesSnapshot

    var body: some View {
        let codex = snapshot.codex
        GroupedList {
            CardHeader("Codex", detail: "~/.codex/config.toml, read only", lead: { CLIDot(.codex, decorative: true) })
            if !codex.present {
                EmptyRow("There is no ~/.codex/config.toml. Codex runs on its defaults.")
            }
            ForEach(keyRows(codex), id: \.key) { row in
                Row { RowText(row.key, mono: true) }
                    .cells { Tag(row.value, tone: row.warn ? .warn : .neutral) }
            }
            if !codex.projects.isEmpty {
                Row { RowText("Project trust levels", subtitle: "\(codex.projects.count) \(codex.projects.count == 1 ? "project" : "projects") in config.toml") }
                    .cells { Tag(CodexCellWording.trustSummary(codex)) }
            }
            if let here = snapshot.selection.dir.flatMap({ dir in codex.projects.first { $0.path == dir } }) {
                Row { RowText("This project", subtitle: "trust_level in config.toml") }
                    .cells { Tag(here.trustLevel ?? "unset") }
            }
        }
    }

    private struct KeyRow {
        let key: String
        let value: String
        var warn = false
    }

    private func keyRows(_ codex: CodexPermissions) -> [KeyRow] {
        var rows: [KeyRow] = []
        let approval = CodexCellWording.approvalText(codex)
        if let approval { rows.append(KeyRow(key: "approval_policy", value: approval, warn: approval == "never")) }
        if let mode = codex.sandboxMode { rows.append(KeyRow(key: "sandbox_mode", value: mode, warn: codex.unrestricted)) }
        if let write = codex.sandboxWorkspaceWrite {
            if let network = write.networkAccess { rows.append(KeyRow(key: "sandbox_workspace_write.network_access", value: String(network))) }
            if !write.writableRoots.isEmpty { rows.append(KeyRow(key: "sandbox_workspace_write.writable_roots", value: "\(write.writableRoots.count) folders")) }
        }
        if let name = codex.defaultPermissions { rows.append(KeyRow(key: "default_permissions", value: name)) }
        if let reviewer = codex.approvalsReviewer { rows.append(KeyRow(key: "approvals_reviewer", value: reviewer)) }
        if codex.present || codex.rules.files > 0 { rows.append(KeyRow(key: "~/.codex/rules", value: CodexCellWording.rulesSummary(codex))) }
        return rows
    }
}
