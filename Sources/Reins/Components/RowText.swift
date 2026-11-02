import SwiftUI

/// The text block of a `Row`: a title with optional tags beside it, and a muted second line.
/// `mono` is for commands and paths.
struct RowText<Tags: View>: View {
    let title: String
    var subtitle: String?
    var mono = false
    let tags: Tags

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(mono ? ReinsFont.monoStrong : ReinsFont.bodyStrong)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                tags
            }
            if let subtitle {
                Text(subtitle)
                    .font(mono ? ReinsFont.mono : ReinsFont.small)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

extension RowText where Tags == EmptyView {
    init(_ title: String, subtitle: String? = nil, mono: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.mono = mono
        self.tags = EmptyView()
    }
}

extension RowText {
    init(_ title: String, subtitle: String? = nil, mono: Bool = false, @ViewBuilder tags: () -> Tags) {
        self.title = title
        self.subtitle = subtitle
        self.mono = mono
        self.tags = tags()
    }
}
