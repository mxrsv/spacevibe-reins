import SwiftUI

/// The Skills detail pane (`DetailPane` and its parts) in the six states of the spec's Components table: normal, never ran, newly
/// added, plugin read-only, one CLI only, nothing selected. Each is the real pane layout over synthetic skills, wording from
/// `SkillsWording`, 720 wide as the pane is at 1440 x 900.
struct PaneSpecimens: View {
    private static let paneHeight: CGFloat = 700
    private static let paneWidth: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            ForEach(Array(Self.states.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: Space.s8) {
                    SpecimenLayout.caption(state.caption)
                    Group {
                        if let row = state.row { pane(row, status: state.status) } else {
                            QuietEmptyState("Nothing selected", message: "Pick a row on the left.", placement: .list)
                        }
                    }
                    .frame(width: Self.paneWidth, height: Self.paneHeight, alignment: .top)
                    .blockSurface(Palette.bgPanel)
                }
            }
        }
    }

    // MARK: Synthetic skills (never the user's)

    private static func item(_ cli: CoreCLI, _ cells: CoreCells, owner: String = "user") -> CoreInventoryItem {
        CoreInventoryItem(
            id: "\(cli.rawValue):skill:global:specimen", cli: cli, kind: .skill, name: "specimen", entry: "specimen",
            description: "Reviews a change you just made before you commit it.", owner: owner,
            path: "~/.\(cli.rawValue)/skills/specimen", file: "~/.\(cli.rawValue)/skills/specimen/SKILL.md", removable: owner == "user",
            scope: .global, project: nil, inOther: false, key: "skill::specimen", cells: cells
        )
    }

    private static func row(claude: CoreUsageCell? = nil, codex: CoreUsageCell? = nil, owner: String = "user") -> LoadoutRow {
        let cells = CoreCells(claude: claude ?? .missing, codex: codex ?? .missing)
        let items = [claude.map { _ in item(.claude, cells, owner: owner) }, codex.map { _ in item(.codex, cells, owner: owner) }].compactMap { $0 }
        let snapshot = CoreLoadoutRows(usage: .ready, items: items, hooks: [], problems: [], events: [:], roots: [:], countsByScope: [:], rowFlags: [:])
        return LoadoutRows.build(snapshot, home: nil)[0]
    }

    private static let states: [(caption: String, row: LoadoutRow?, status: SkillStatus)] = [
        ("Normal: in both CLIs, ran in each", row(claude: .counted(runs: 87, last: "2026-11-05", errors: nil), codex: .counted(runs: 31, last: "2026-11-01", errors: nil)), .ran),
        ("Never ran: warn verdict, a zero and a bar with nothing in it", row(claude: .counted(runs: 0, last: nil, errors: nil)), .neverRan),
        ("Newly added: Never ran with the neutral clock's note, not a candidate to remove yet", row(claude: .pending(reason: "Added in the last 24 hours")), .neverRan),
        ("Plugin read-only: the tag, a disabled Remove and the note", row(claude: .counted(runs: 11, last: "2026-11-04", errors: nil), owner: "neon"), .ran),
        ("One CLI only: Add to Codex is the primary action", row(claude: .counted(runs: 142, last: "2026-11-06", errors: nil)), .heavy),
        ("Nothing selected", nil, .loading),
    ]

    // MARK: The pane, drawn from the model's own sentences

    private func pane(_ row: LoadoutRow, status: SkillStatus) -> some View {
        let detected: [CoreCLI] = [.claude, .codex]
        let now = Date()
        return DetailPane {
            PaneHead(name: row.name, glyph: CategoryGlyph.skill, tone: .skill, pluginTag: row.plugin.map { "plugin: \($0)" }, meta: ["Skill", "Global"]) {
                LogoStrip {
                    ForEach(detected, id: \.self) { cli in
                        LogoToggle(cli: CoreLimitsCLI(cli), isLit: row.members[cli] != nil, mode: row.plugin != nil ? .readOnly : .toggles) {}
                    }
                }
            }
            Text(row.detail).spaceVibeText(.prose, tone: .secondary).lineBox(.prose)
            if let verdict = SkillsWording.verdict(for: row, status: status, detected: detected) {
                VerdictBox(glyph: status.verdict, glyphLabel: verdict.title, title: verdict.title, text: verdict.text, small: verdict.small)
            }
            PaneSection(title: "Sessions by CLI") {
                SessionMeters(meters: detected.map { SkillsWording.meter(for: row, cli: $0, maxSessions: 142, now: now) })
            }
            PaneSection(title: "Lives in") {
                FileList(files: CoreCLI.allCases.compactMap { cli in row.members[cli].map { _ in FileList.Entry(cli: cli, path: "~/.\(cli.rawValue)/skills/specimen/SKILL.md") } })
            }
            VStack(alignment: .leading, spacing: Metrics.DetailPane.noteAbove) {
                HStack(spacing: Metrics.DetailPane.actionSpacing) {
                    if row.members[.codex] == nil && row.plugin == nil {
                        Button {} label: { ActionLabel("Add to Codex", key: "A") }.buttonStyle(ActionButtonStyle(kind: .primary))
                    }
                    Button {} label: { ActionLabel("Remove", glyph: .trash, key: "R") }
                        .buttonStyle(ActionButtonStyle(kind: .danger)).disabled(row.plugin != nil)
                    Button {} label: { ActionLabel("Open", glyph: .open, key: "O") }.buttonStyle(ActionButtonStyle())
                }
                if let plugin = row.plugin {
                    PopoverNote("Owned by the \(plugin) plugin. Remove it by uninstalling the plugin.", glyph: .lock)
                }
            }
        }
    }
}
