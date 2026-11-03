import ReinsCore

/// The Loadout entries of the `⌘K` palette. Actions show while the tab is active; items are searched from any tab once the
/// user has typed. Every entry performs a real change or a jump; nothing here runs a hook.
extension LoadoutModel {
    var paletteActions: [PaletteEntry] {
        guard let data else { return [] }
        var out: [PaletteEntry] = []
        for row in data.rows where row.project == nil && row.flags.dead {
            for member in row.removableMembers {
                out.append(PaletteEntry(
                    id: "loadout.remove-dead.\(member.id)",
                    title: "Remove dead hook \(row.name)",
                    subtitle: "\(member.cli.label): \(row.detail)",
                    icon: .trash,
                    keywords: ["delete", "hook", "script not found"]
                ) { [weak self] in self?.remove(row, member: member) })
            }
        }
        for cli in InventoryCLI.allCases {
            let count = deadHookCount(cli: cli)
            guard count > 1 else { continue }
            out.append(PaletteEntry(
                id: "loadout.remove-all-dead.\(cli.rawValue)",
                title: "Remove all \(count) dead hooks from \(cli.label)",
                icon: .trash,
                keywords: ["delete", "hooks", "script not found"]
            ) { [weak self] in self?.removeDeadHooks(cli: cli) })
        }
        return out
    }

    var paletteItems: [PaletteEntry] {
        guard let data else { return [] }
        var out: [PaletteEntry] = []
        for row in data.rows {
            for cli in InventoryCLI.allCases where LoadoutRows.copyPlan(row, to: cli, events: data.events) != nil {
                out.append(PaletteEntry(
                    id: "loadout.copy.\(row.key).\(cli.rawValue)",
                    title: "Copy \(row.kind.noun) \(row.name) to \(cli.label)",
                    subtitle: "Loadout",
                    icon: .copy,
                    keywords: ["add", "install"]
                ) { [weak self] in self?.add(row, to: cli) })
            }
        }
        for row in data.rows {
            out.append(PaletteEntry(
                id: "loadout.go.\(row.key)",
                title: row.name,
                subtitle: subtitle(for: row),
                icon: .arrowRight,
                keywords: [row.kind.noun]
            ) { [weak self] in self?.jump(to: row) })
        }
        return out
    }

    private func subtitle(for row: LoadoutRow) -> String {
        guard let project = row.project else { return row.kind.sectionTitle }
        return "\(row.kind.sectionTitle) in \(project.split(separator: "/").last.map(String.init) ?? project)"
    }
}
