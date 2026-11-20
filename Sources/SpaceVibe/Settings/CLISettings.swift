import SwiftUI

/// Settings > Appearance > CLIs (spec `docs/specs/2026-11-19-multi-cli.md`, MC3, MC9, MC-R4): every CLI the core's `clis.list`
/// describes, in its order, each with its mark, its name, "Not installed" when it is not on this Mac, and a switch. A CLI turned
/// off leaves every page and every "missing in" comparison (the filter in `CLICatalog`); a CLI listed for the first time is on.
struct CLISettings: View {
    let env: AppEnvironment
    let isOpen: Binding<Bool>

    var body: some View {
        Tile(SettingsWording.clis, isOpen: isOpen) {
            ListRows {
                ForEach(env.catalog.all, id: \.id) { cli in
                    ListRow(cli.label, accessibilityName: SettingsWording.cliSpoken(cli.label, installed: cli.installed)) {
                        CLIMark(cli.id, size: .control)
                    } trailing: {
                        if !cli.installed { MetaCell(text: SettingsWording.cliNotInstalled) }
                        SpaceVibeSwitch(label: cli.label, isOn: Binding(
                            get: { env.catalog.isEnabled(cli.id) },
                            set: { env.setCLI(cli.id, on: $0) }))
                    }
                }
            }
        }
        // Whether a CLI is installed can change while the app runs; the list is read again each time the group appears.
        .task { await env.loadCLIs() }
    }
}
