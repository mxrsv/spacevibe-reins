import ReinsCore
import SwiftUI

/// One live session: title, project and current tool, the state tag (the engine's reason is its help text), the
/// estimated cost, and Stop.
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
                title: Text(session.title).font(fallback ? ReinsFont.monoStrong : ReinsFont.bodyStrong).foregroundStyle(Palette.text),
                lines: [wording.subtitle],
                help: session.title
            )
        }
        .lead { CLIDot(session.cli, decorative: true) }
        .cells {
            HStack(spacing: Metrics.rowSpacing) {
                Tag(wording.tagText, tone: wording.tagTone, systemImage: wording.tagIcon)
                    .help(wording.help)
                    .accessibilityHint(wording.help)
                costCell
            }
        }
        .actions { RowActionButton(title: "Stop", kind: .normal, action: onStop) }
        .accessibilityLabel("\(session.cli.label), \(session.title), \(wording.tagText)")
    }

    @ViewBuilder
    private var costCell: some View {
        Group {
            if let cost = session.cost {
                Text(ActivityFormat.cost(cost.usd)).foregroundStyle(Palette.text).help(Self.costHelp)
            } else {
                Text("\u{2014}").foregroundStyle(Palette.textTertiary)
                    .help(session.costNote ?? "No cost estimate.")
                    .accessibilityLabel("no cost estimate")
            }
        }
        .font(ReinsFont.small)
        .frame(width: 58, alignment: .trailing)
    }
}
