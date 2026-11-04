import ReinsCore
import SwiftUI

/// One live session: title, project and current tool, the state tag in its fixed column (the engine's reason is its help
/// text), the estimated cost, and Stop.
struct ActivitySessionRow: View {
    let session: ActivitySession
    let elapsedMs: Double
    var revealActions = false
    let onStop: () -> Void

    private static let costHelp = "Estimated from the tokens in the log at API list prices (API-equivalent). It is not what a subscription bills."

    var body: some View {
        let wording = SessionWording(session, elapsedMs: elapsedMs)
        let fallback = ActivityFormat.isFallbackTitle(session.title)
        Row(revealActions: revealActions) {
            ActivityLines(
                title: Text(session.title).reinsText(fallback ? .codeTitle : .rowTitle, tone: .primary),
                lines: [ActivityLines.Line(wording.subtitle)],
                help: session.title
            )
        }
        .lead { CLIDot(session.cli, decorative: true) }
        .cells {
            StateCell {
                Tag(wording.tagText, tone: wording.tagTone, icon: wording.tagIcon)
                    .help(wording.help)
                    .accessibilityHint(wording.help)
            }
            costCell
        }
        .actions { RowActionButton(title: "Stop", icon: .stop, iconOnly: true, action: onStop) }
        .accessibilityLabel("\(session.cli.label), \(session.title), \(wording.tagText)")
    }

    @ViewBuilder
    private var costCell: some View {
        if let cost = session.cost {
            NumberCell(text: ActivityFormat.cost(cost.usd)).help(Self.costHelp)
        } else {
            NumberCell(text: "\u{2014}", muted: true)
                .help(session.costNote ?? "No cost estimate.")
                .accessibilityLabel("no cost estimate")
        }
    }
}
