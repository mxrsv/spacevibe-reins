import SwiftUI

/// Settings > Update: the lead card (the SpaceVibe mark, version and build, the last check's result and time, one button) and
/// the automatic-check switch. Opening it never starts a check.
struct UpdateSettings: View {
    @Environment(UpdateController.self) private var updates

    var body: some View {
        @Bindable var updates = updates
        VStack(spacing: Rhythm.cards) {
            ContentCard {
                HStack(spacing: Space.s16) {
                    SpaceVibeMark()
                    VStack(alignment: .leading, spacing: Space.s6) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s6) {
                            Text(SettingsWording.appName(version: updates.version)).spaceVibeText(.title, tone: .primary)
                            if let build = updates.build { Text("Build \(build)").spaceVibeText(.caption, tone: .tertiary) }
                        }
                        status
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    action
                }
                if case .unavailable(let reason) = updates.status {
                    RaisedBlock {
                        HStack(alignment: .top, spacing: Space.s8) {
                            SpaceVibeIcon(.info).foregroundStyle(TextTone.secondary.color)
                            Text(reason).spaceVibeText(.body, tone: .secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, Space.s24)
                }
            }

            GroupedList {
                Row { RowText(SettingsWording.automaticChecks, subtitle: SettingsWording.automaticChecksDetail) }
                    .lead { SpaceVibeIcon(.refresh, size: .row) }
                    .cells {
                        SpaceVibeSwitch(label: SettingsWording.automaticChecks, isOn: $updates.automaticChecks)
                            .disabled(!updates.isRunning)
                    }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        let tag = SettingsWording.tag(updates.status)
        let time = SettingsWording.lastCheck(updates.status, at: updates.lastCheck, now: Date())
        if tag != nil || time != nil {
            HStack(spacing: Space.s8) {
                if let tag { Tag(tag.text, tone: tag.tone, icon: tag.icon) }
                if let time { Text(time).spaceVibeText(.caption, tone: .tertiary) }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var action: some View {
        if case .available = updates.status {
            Button("View Update") { updates.checkForUpdates() }
                .buttonStyle(.spaceVibe(.primary))
        } else {
            Button("Check Now") { updates.checkNow() }
                .buttonStyle(.spaceVibe())
                .disabled(!updates.isRunning || updates.status == .checking)
        }
    }
}
