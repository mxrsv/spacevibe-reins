import AppKit

/// The licences the app must show: the bundled typeface and the icon set. Shown in the standard About panel (Reins menu,
/// About Reins), which has no other credits.
enum Credits {
    /// CC BY 4.0 asks for the author, the licence with its link, and a note of what was changed.
    static let icons = "Icons: Solar by 480 Design, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Converted to SwiftUI paths; each icon's lighter shapes are drawn as one layer."
    static let typeface = "Typeface: Inter, copyright 2016 The Inter Project Authors (https://github.com/rsms/inter), SIL Open Font License 1.1."

    static var text: String { [icons, typeface].joined(separator: "\n\n") }

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
