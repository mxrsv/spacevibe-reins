import SwiftUI

/// The frame every screen sits in below the shell's top bar: an optional tools row (filters, selectors)
/// and a scrolling body, both inset by the page padding.
struct PageLayout<Tools: View, Content: View>: View {
    let tools: Tools
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            tools
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            ReinsScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
            }
        }
    }
}

extension PageLayout where Tools == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.tools = EmptyView()
        self.content = content()
    }
}

extension PageLayout {
    init(@ViewBuilder tools: () -> Tools, @ViewBuilder content: () -> Content) {
        self.tools = tools()
        self.content = content()
    }
}
