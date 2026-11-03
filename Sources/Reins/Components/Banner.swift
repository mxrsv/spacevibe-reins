import SwiftUI

enum BannerKind {
    case error, warn

    var systemImage: String { self == .error ? "xmark.octagon" : "exclamationmark.triangle" }
    var ink: Color { self == .error ? Palette.dangerInk : Palette.warnInk }
    var tint: Color { self == .error ? Palette.dangerTint : Palette.warnTint }
    var outline: Color { self == .error ? Palette.danger : Palette.warn }
    var spoken: String { self == .error ? "Error" : "Warning" }
}

/// A message about state that needs attention (a file that failed to parse, a scan that could not finish), with
/// an optional action. Tinted fill and a full hairline border; no coloured side stripe.
struct Banner: View {
    let kind: BannerKind
    let message: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ kind: BannerKind, message: String, detail: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.kind = kind
        self.message = message
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.groupRadius, style: .continuous)
        HStack(alignment: .center, spacing: Metrics.rowSpacing) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.ink)
                .frame(width: Metrics.rowLeadWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(message).reinsText(.bodyStrong, tone: .primary)
                if let detail { Text(detail).reinsText(.caption, tone: .secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.reins(.normal))
            }
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .padding(.vertical, Space.s12)
        .background(shape.fill(kind.tint))
        .overlay(shape.strokeBorder(kind.outline.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind.spoken): \(message)")
    }
}
