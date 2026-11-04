import ReinsCore
import SwiftUI

/// One failed command (or hook), repeats grouped. One title form: the command, as code. The lines under it say how it
/// failed and where, the machine's own message as code; a later passing run is stated as a fact and never as a fix. The
/// repeat count sits in the cost column of the session rows above it, and an empty slot keeps the Stop column.
struct ActivityFailureRow: View {
    let failure: ActivityFailure
    let now: Date

    private static let repeatAlert = 5

    var body: some View {
        let wording = FailureWording(failure, now: now)
        let isHook = failure.kind == .hook
        Row(tall: true) {
            ActivityLines(
                title: Text(failure.title).reinsText(.codeTitle, tone: .primary),
                lines: [ActivityLines.Line(wording.how)]
                    + [wording.reason.map { ActivityLines.Line($0, code: true) }, wording.laterPass.map { ActivityLines.Line($0) }].compactMap { $0 },
                help: failure.title
            )
        }
        .lead {
            if isHook {
                ReinsIcon(.hook, size: .row, label: "Hook")
            } else {
                CLIDot(failure.cli, decorative: true)
            }
        }
        .cells {
            FixedCell {
                if failure.count > 1 {
                    Tag("\u{00D7}\(failure.count)", tone: failure.count >= Self.repeatAlert ? .danger : .neutral)
                }
            }
        }
        .actions { EmptyActionSlot() }
        .accessibilityLabel("\(failure.cli.label), \(failure.title), failed \(failure.count) \(failure.count == 1 ? "time" : "times")")
    }
}
