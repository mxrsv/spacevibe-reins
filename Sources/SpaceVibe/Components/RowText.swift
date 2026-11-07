import SwiftUI

/// The text block of a `Row`: a name with optional tags beside it, and muted lines below. The name is `rowTitle`, or
/// `codeTitle` when it is a machine string (a command, a rule pattern); a second line is `caption`, or `code` for a
/// command or path. Prose is never set as code. The name's line keeps its 20 pt line box even beside a 24 pt tag, so a row
/// with tags stays 48 high (the tag reaches 2 pt above and below the line).
struct RowText<Tags: View>: View {
    let title: String
    var subtitle: String?
    var codeTitle = false
    var codeSubtitle = false
    let tags: Tags

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s8) {
                Text(title)
                    .reinsText(codeTitle ? .codeTitle : .rowTitle, tone: .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                tags
            }
            .frame(height: ReinsType.rowTitle.lineBox)
            if let subtitle {
                Text(subtitle)
                    .reinsText(codeSubtitle ? .code : .caption, tone: .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minHeight: ReinsType.caption.lineBox)
            }
        }
    }
}

extension RowText where Tags == EmptyView {
    /// `mono` sets both lines as machine strings.
    init(_ title: String, subtitle: String? = nil, mono: Bool = false, codeSubtitle: Bool? = nil) {
        self.title = title
        self.subtitle = subtitle
        codeTitle = mono
        self.codeSubtitle = codeSubtitle ?? mono
        tags = EmptyView()
    }
}

extension RowText {
    init(_ title: String, subtitle: String? = nil, mono: Bool = false, codeSubtitle: Bool? = nil, @ViewBuilder tags: () -> Tags) {
        self.title = title
        self.subtitle = subtitle
        codeTitle = mono
        self.codeSubtitle = codeSubtitle ?? mono
        self.tags = tags()
    }
}
