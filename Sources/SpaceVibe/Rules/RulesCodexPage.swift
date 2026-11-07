import Foundation
import SwiftUI

/// The Codex page of Rules, read only: how Codex runs in one sentence, the settings behind it with every option written
/// out and the real one picked, the command rules counted per decision, and project trust.
struct RulesCodexPage: View {
    let model: RulesModel
    let snapshot: RulesSnapshot

    /// Project trust lists this many projects before "Show more".
    static let trustPreview = 8

    var body: some View {
        let codex = snapshot.codex
        let status = CodexWording.status(codex)
        VStack(alignment: .leading, spacing: Rhythm.cards) {
            StatusLead(tone: status.tone, sentence: status.sentence, detail: status.detail)
            // At a project only the trust level is the project's own, so it comes first there.
            if snapshot.selection.dir != nil { trust(codex) }
            settings(codex)
            commandRules(codex)
            if snapshot.selection.dir == nil { trust(codex) }
        }
    }

    private func settings(_ codex: CoreCodexPermissions) -> some View {
        GroupedList {
            CardHeader("How Codex runs", detail: "~/.codex/config.toml", columns: { Tag("Read only", icon: .lock) })
            if codex.notReadable {
                EmptyRow(CodexWording.notReadableSentence)
            } else if !codex.present {
                EmptyRow("There is no ~/.codex/config.toml, so Codex runs on its defaults.")
            }
            ForEach(CodexWording.rows(codex), id: \.title) { row in
                Row { RowText(row.title, subtitle: row.key, codeSubtitle: row.keyIsCode) }
                    .cells {
                        CodexValueCell(row: row).frame(width: Metrics.rulesCodexColumn, alignment: .leading)
                    }
            }
        }
    }

    private func commandRules(_ codex: CoreCodexPermissions) -> some View {
        let rules = codex.rules
        return GroupedList {
            CardHeader("Command rules", count: rules.allow + rules.prompt + rules.forbidden + rules.other, detail: "~/.codex/rules")
            if rules.files == 0 {
                EmptyRow("There is no rules file in ~/.codex/rules.")
            } else {
                ForEach(CodexWording.ruleCounts(codex), id: \.title) { item in
                    Row { RowText(item.title, subtitle: item.meaning) }
                        .cells { NumberCell(text: "\(item.count)", muted: item.count == 0) }
                }
                EmptyRow("SpaceVibe counts these rules and does not show their commands, which can hold a secret.")
            }
        }
    }

    @ViewBuilder
    private func trust(_ codex: CoreCodexPermissions) -> some View {
        if let dir = snapshot.selection.dir {
            let project = codex.projects.first { $0.path == dir }
            GroupedList {
                CardHeader("This project", detail: "trust_level in config.toml")
                if codex.notReadable {
                    EmptyRow(CodexWording.trustNotReadableSentence)
                } else {
                    CodexTrustRow(path: dir, level: project?.trustLevel, listed: project != nil)
                }
                EmptyRow("Codex reads no permission file inside a project: everything above comes from ~/.codex/config.toml.")
            }
        } else {
            let shown = model.showsAllTrust ? codex.projects : Array(codex.projects.prefix(Self.trustPreview))
            GroupedList {
                CardHeader("Project trust", count: codex.notReadable ? nil : codex.projects.count, detail: "[projects] in config.toml")
                if codex.notReadable {
                    EmptyRow(CodexWording.trustNotReadableSentence)
                } else if codex.projects.isEmpty {
                    EmptyRow("config.toml lists no project.")
                }
                ForEach(shown, id: \.path) { project in
                    CodexTrustRow(path: project.path, level: project.trustLevel, listed: true)
                }
                if codex.projects.count > shown.count {
                    ShowMoreRow(reveal: codex.projects.count - shown.count, hiddenAfter: 0) { model.showAllTrust() }
                }
            }
        }
    }
}

/// The value of one setting: every option with the real one picked, or a tag.
private struct CodexValueCell: View {
    let row: CodexSettingRow

    var body: some View {
        switch row.value {
        case .options(let options, let picked, let warn):
            SegmentReadout(label: row.title, options: options, selected: picked, warn: warn)
        case .tag(let text, let tone):
            Tag(text, tone: tone)
        }
    }
}

/// A project's folder name, its path and its trust level.
private struct CodexTrustRow: View {
    let path: String
    let level: String?
    let listed: Bool

    var body: some View {
        let tag = listed ? CodexWording.trustTag(level) : (text: "not listed", tone: TagTone.neutral)
        Row { RowText(URL(fileURLWithPath: path).lastPathComponent, subtitle: (path as NSString).abbreviatingWithTildeInPath, codeSubtitle: true) }
            .cells {
                Tag(tag.text, tone: tag.tone).frame(width: Metrics.rulesCodexColumn, alignment: .leading)
            }
    }
}
