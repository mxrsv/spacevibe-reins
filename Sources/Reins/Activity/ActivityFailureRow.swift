import ReinsCore
import SwiftUI

/// One failed command (or hook), repeats grouped. One title form: the command, in monospace. The lines under it say how
/// it failed and where; a later passing run is stated as a fact and never as a fix.
struct ActivityFailureRow: View {
    let failure: ActivityFailure
    let now: Date

    private static let repeatAlert = 5

    var body: some View {
        let wording = FailureWording(failure, now: now)
        let isHook = failure.kind == .hook
        Row {
            ActivityLines(
                title: Text(failure.title).font(ReinsFont.monoStrong).foregroundStyle(Palette.text),
                lines: [wording.how] + [wording.reason, wording.laterPass].compactMap { $0 },
                help: failure.title
            )
        }
        .lead {
            if isHook {
                Image(systemName: "bolt").accessibilityLabel("Hook")
            } else {
                CLIDot(failure.cli, decorative: true)
            }
        }
        .cells {
            if failure.count > 1 {
                Tag("\u{00D7}\(failure.count)", tone: failure.count >= Self.repeatAlert ? .danger : .neutral)
            }
        }
        .accessibilityLabel("\(failure.cli.label), \(failure.title), failed \(failure.count) \(failure.count == 1 ? "time" : "times")")
    }
}
