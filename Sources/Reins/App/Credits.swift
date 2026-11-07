import AppKit

/// The licences the app must show: the bundled typeface, the icon set and the Go library inside the bundled core. Shown in the standard About panel (Reins menu,
/// About Reins), which has no other credits.
enum Credits {
    /// CC BY 4.0 asks for the author, the licence with its link, and a note of what was changed.
    static let icons = "Icons: Solar by 480 Design, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Converted to SwiftUI paths; each icon's lighter shapes are drawn as one layer."
    static let typeface = "Typeface: Inter, copyright 2016 The Inter Project Authors (https://github.com/rsms/inter), SIL Open Font License 1.1."

    /// BSD 3-Clause asks binary redistributions to reproduce the copyright notice, the conditions and the disclaimer.
    /// The text is the head of the module's LICENSE (v1.20.3). The Snappy-Go line is there because the Zstandard package
    /// links internal/snapref, a copy of Snappy-Go under the same terms.
    static let compress = """
    Zstandard decoder in the bundled core: github.com/klauspost/compress

    Copyright (c) 2012 The Go Authors. All rights reserved.
    Copyright (c) 2019 Klaus Post. All rights reserved.
    Copyright (c) 2011 The Snappy-Go Authors. All rights reserved.

    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of Google Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    """

    static var text: String { [icons, typeface, compress].joined(separator: "\n\n") }

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
