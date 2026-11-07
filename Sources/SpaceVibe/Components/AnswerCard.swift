import SwiftUI

/// The first card of a split page (V5-R53): the card titled `Answer`, holding one sentence at the primary-datum size, then
/// optionally a verdict box, the fix actions and a note that more rows are marked. The page derives every part from its data
/// in one model function; this block only lays them out. While the page loads, `sentence` is nil and the card shows the
/// skeleton. When nothing needs the user, the page passes the plain sentence and no verdict, fixes or `moreMarked`.
///
///     AnswerCard(sentence: answer.sentence, verdict: answer.verdict, moreMarked: answer.more, isOpen: $open) {
///         Button("Remove") { ... }
///     }
struct AnswerCard<Fixes: View, HeaderActions: View>: View {
    static var title: String { "Answer" }

    /// Nil while loading.
    let sentence: String?
    var verdict: VerdictBox?
    /// Rows that need the user beyond the one the sentence names: "N more are marked in the list."
    var moreMarked = 0
    @Binding var isOpen: Bool
    let headerActions: HeaderActions
    let fixes: Fixes

    var body: some View {
        if let sentence {
            Tile(Self.title, layout: .content, isOpen: $isOpen) { answerBody(sentence) } actions: { headerActions }
        } else {
            Tile(Self.title, layout: .bare, isOpen: $isOpen) { LoadingSkeleton() } actions: { headerActions }
        }
    }

    @ViewBuilder
    private func answerBody(_ sentence: String) -> some View {
        Text(sentence)
            .spaceVibeText(.answer, tone: .primary)
            .fixedSize(horizontal: false, vertical: true)
            .lineBox(.answer)
            .accessibilityAddTraits(.isHeader)
        if let verdict { verdict }
        if Fixes.self != EmptyView.self {
            HStack(spacing: Metrics.Tile.headerSpacing) { fixes }
        }
        if moreMarked > 0 {
            Text("\(moreMarked) more \(moreMarked == 1 ? "is" : "are") marked in the list.")
                .spaceVibeText(.meta, tone: .tertiary)
                .lineBox(.meta)
        }
    }
}

extension AnswerCard where HeaderActions == EmptyView {
    init(sentence: String?, verdict: VerdictBox? = nil, moreMarked: Int = 0, isOpen: Binding<Bool>,
         @ViewBuilder fixes: () -> Fixes) {
        self.init(sentence: sentence, verdict: verdict, moreMarked: moreMarked, isOpen: isOpen, headerActions: EmptyView(), fixes: fixes())
    }
}

extension AnswerCard where Fixes == EmptyView, HeaderActions == EmptyView {
    init(sentence: String?, verdict: VerdictBox? = nil, moreMarked: Int = 0, isOpen: Binding<Bool>) {
        self.init(sentence: sentence, verdict: verdict, moreMarked: moreMarked, isOpen: isOpen, headerActions: EmptyView(), fixes: EmptyView())
    }
}

extension AnswerCard {
    init(sentence: String?, verdict: VerdictBox? = nil, moreMarked: Int = 0, isOpen: Binding<Bool>,
         @ViewBuilder fixes: () -> Fixes, @ViewBuilder headerActions: () -> HeaderActions) {
        self.init(sentence: sentence, verdict: verdict, moreMarked: moreMarked, isOpen: isOpen, headerActions: headerActions(), fixes: fixes())
    }
}

/// A verdict in a sunk box (V5-R14, V5-R53): the neutral verdict glyph (20), the title in 500 ending in a full stop, the
/// sentence after it, and an optional quieter line under them. The Answer card and the Skills pane use it.
struct VerdictBox: View {
    let glyph: VerdictGlyph.Kind
    /// What VoiceOver reads for the glyph, for example "Advice" or "Never ran".
    let glyphLabel: String
    let title: String
    let text: String
    var small: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle)
        HStack(alignment: .top, spacing: Metrics.VerdictBox.spacing) {
            VerdictGlyph(glyph, size: .row, label: glyphLabel)
            VStack(alignment: .leading, spacing: Metrics.VerdictBox.smallAbove) {
                (Text("\(title). ").spaceVibeText(.control, tone: .primary) + Text(text).spaceVibeText(.prose, tone: .primary))
                    .lineSpacing(SpaceVibeType.prose.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineBox(.prose)
                if let small {
                    Text(small).spaceVibeText(.meta, tone: .tertiary).fixedSize(horizontal: false, vertical: true).lineBox(.meta)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Metrics.VerdictBox.padding)
        // Inside the 1 pt edge, as the kit's border does (CSS border-box).
        .padding(Metrics.Radius.edge)
        .background(shape.fill(Palette.bgSunk))
        .overlay(shape.strokeBorder(Palette.hair, lineWidth: Metrics.Radius.edge))
        .accessibilityElement(children: .combine)
    }
}
