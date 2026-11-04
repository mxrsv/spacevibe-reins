/// The Rules entries of the `⌘K` palette. Actions show while the tab is active; the scope jumps are searched from any tab once
/// the user has typed. Nothing here writes: adding a rule only moves the focus to the field. Every Claude Code entry opens
/// the Claude Code page; "Rules: Codex" opens the Codex page.
extension RulesModel {
    var paletteActions: [PaletteEntry] {
        guard snapshot != nil else { return [] }
        return [
            PaletteEntry(id: "rules.add", title: "Add a Claude Code rule", icon: .add, keywords: ["permission", "allow", "deny", "ask", "new"]) { [weak self] in
                self?.focusAddRule()
            },
            PaletteEntry(id: "rules.refresh", title: "Refresh rules", icon: .refresh, keywords: ["reload", "permissions"]) { [weak self] in
                self?.refresh()
            },
        ]
    }

    var paletteItems: [PaletteEntry] {
        guard let snapshot else { return [] }
        var out = [jumpEntry(id: "rules.go.global", title: "Rules: Global", subtitle: "~/.claude/settings.json", choice: .global)]
        out.append(PaletteEntry(id: "rules.go.codex", title: "Rules: Codex", subtitle: "~/.codex/config.toml", icon: .arrowRight, keywords: ["permissions", "sandbox", "approval"]) { [weak self] in
            self?.jumpToCodex()
        })
        for project in snapshot.projects {
            out.append(jumpEntry(id: "rules.go.shared.\(project.dir)", title: "Rules: \(project.name)", subtitle: ".claude/settings.json", choice: RulesSelection(dir: project.dir, file: .shared)))
            out.append(jumpEntry(id: "rules.go.local.\(project.dir)", title: "Rules: \(project.name) (local)", subtitle: ".claude/settings.local.json", choice: RulesSelection(dir: project.dir, file: .local)))
        }
        return out
    }

    private func jumpEntry(id: String, title: String, subtitle: String, choice: RulesSelection) -> PaletteEntry {
        PaletteEntry(id: id, title: title, subtitle: subtitle, icon: .arrowRight, keywords: ["permissions", "scope"]) { [weak self] in
            self?.jump(to: choice)
        }
    }
}
