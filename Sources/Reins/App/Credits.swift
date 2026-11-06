import AppKit

/// The licences the app must show: the bundled typeface and the two icon sets. Shown in the standard About panel (Reins
/// menu, About Reins), which has no other credits.
enum Credits {
    /// CC BY 4.0 asks for the author, the licence with its link, and a note of what was changed.
    static let icons = "Sidebar icons: Solar by 480 Design, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Converted to SwiftUI paths; each icon's lighter shapes are drawn as one layer."
    /// MIT asks for the copyright notice and the permission notice in every copy.
    static let pageIcons = """
        Page icons: Tabler Icons (https://github.com/tabler/tabler-icons), converted to SwiftUI paths. MIT License.

        Copyright (c) 2020-2026 Paweł Kuna

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
        documentation files (the "Software"), to deal in the Software without restriction, including without limitation the \
        rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit \
        persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the \
        Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE \
        WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR \
        COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR \
        OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    static let typeface = "Typeface: Inter, copyright 2016 The Inter Project Authors (https://github.com/rsms/inter), SIL Open Font License 1.1."

    static var text: String { [icons, pageIcons, typeface].joined(separator: "\n\n") }

    @MainActor
    static func showAboutPanel() {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
        // Inter, like the rest of the app; registering it is what `ReinsType` does on first use.
        if InterFont.isRegistered, let font = NSFont(name: InterFont.Weight.regular.postScriptName, size: ReinsType.caption.size) {
            attributes[.font] = font
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: text, attributes: attributes)])
    }
}
