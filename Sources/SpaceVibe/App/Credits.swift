import AppKit

/// The licences the app must show: the bundled typeface, the three icon sets, the Sparkle updater, and the Go runtime and library inside the bundled core. Shown in the standard About panel (SpaceVibe menu,
/// About SpaceVibe), which has no other credits.
enum Credits {
    /// Solar draws the old screens, until the v5 cut-over deletes them. CC BY 4.0 asks for the author, the licence with its link, and a note of what was changed.
    static let icons = "Icons: Solar by 480 Design, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Converted to SwiftUI paths; each icon's lighter shapes are drawn as one layer."
    /// Apache-2.0 section 4(a) asks for a copy of the licence to go with the glyphs. It ships as a file in the bundle, beside
    /// Inter's `OFL.txt`: `Resources/Licenses/MingCute-Apache-2.0.txt` is the upstream `LICENSE` (mingcute-design/mingcute-icons,
    /// blob d645695, last changed in bcee804, 2026-07-30), copied by `scripts/build-app.sh` into `Contents/Resources/Licenses/`.
    /// Section 4(b) asks for a note that the files changed; the header of the generated `CategoryIconData.swift` carries it too.
    /// The upstream `LICENSE` is the unfilled template (no copyright line) and the repository has no `NOTICE` file.
    static let categoryIcons = "Category icons: MingCute by MingCute Design, Apache-2.0 (https://www.apache.org/licenses/LICENSE-2.0). Converted to SwiftUI paths (changed from the original). The licence text is in the app bundle: Contents/Resources/Licenses/MingCute-Apache-2.0.txt."

    /// MIT asks for the copyright notice and the permission notice in all copies or substantial portions.
    static let contentIcons = """
    Sidebar and content icons: Phosphor Icons (https://github.com/phosphor-icons/core), MIT. Converted to SwiftUI paths and scaled (changed from the original).

    Copyright (c) 2023 Phosphor Icons

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
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

    /// The Zstandard package links zstd/internal/xxhash, a copy of Caleb Spare's xxhash under the MIT licence, which asks
    /// for the notice to travel with copies. The text is that directory's LICENSE.txt (v1.20.3).
    static let xxhash = """
    Zstandard decoder, xxhash checksum: github.com/cespare/xxhash (copy inside github.com/klauspost/compress)

    Copyright (c) 2016 Caleb Spare

    MIT License

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
    LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
    OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    /// MIT asks for the copyright and permission notice in all copies. Sparkle's `LICENSE` carries the MIT text for the framework and the
    /// notices of the parts it bundles (bsdiff and sais-lite, ed25519, SUSignatureVerifier), so the whole file ships unchanged as
    /// `Resources/Licenses/Sparkle-MIT.txt` (v2.10.0, the release `Package.swift` pins), copied by `scripts/build-app.sh` into
    /// `Contents/Resources/Licenses/`. `Sparkle.framework` is embedded in the app; the credit names the main copyright holders.
    static let sparkle = "Updates: Sparkle (https://sparkle-project.org), MIT; copyright (c) 2006-2017 Andy Matuschak, Elgato Systems GmbH, Kornel Lesiński and Mayur Pawashe, and others. The framework bundles bsdiff, sais-lite, ed25519 and SUSignatureVerifier under their own licences. The full text is in the app bundle: Contents/Resources/Licenses/Sparkle-MIT.txt."

    /// BSD 3-Clause asks binary redistributions to reproduce the copyright notice, the conditions and the disclaimer. The Go runtime and the
    /// standard library are linked statically into the bundled core binary. The text is the toolchain's `LICENSE` (Go 1.26.10, as `core/go.mod`); the same
    /// file ships as `Resources/Licenses/Go-BSD-3-Clause.txt`.
    static let goRuntime = """
    Go runtime and standard library in the bundled core (https://go.dev)

    Copyright 2009 The Go Authors.

    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of Google LLC nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    """

    static var text: String { [icons, categoryIcons, contentIcons, typeface, sparkle, goRuntime, compress, xxhash].joined(separator: "\n\n") }

    @MainActor
    static func showAboutPanel() {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
        // Inter, like the rest of the app; registering it is what `SpaceVibeType` does on first use.
        if InterFont.isRegistered, let font = NSFont(name: InterFont.Weight.regular.postScriptName, size: SpaceVibeType.caption.size) {
            attributes[.font] = font
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: text, attributes: attributes)])
    }
}
