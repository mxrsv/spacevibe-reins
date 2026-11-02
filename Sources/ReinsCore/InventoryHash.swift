import Foundation

extension Inventory {
    /// First 12 hex digits of the SHA-1 of the UTF-8 text. Hook ids and hook identity are built from it (`sha` in core/inventory.mjs).
    public static func sha(_ text: String) -> String {
        Sha1.digest(Array(text.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// The part after the last `:` of a plugin-qualified name (`plugin:skill` -> `skill`).
    public static func bare(_ name: String) -> String {
        name.split(separator: ":", omittingEmptySubsequences: false).last.map(String.init) ?? name
    }

    /// Identity of a hook in the logs: event plus command. Hashing the command alone inflates run counts.
    public static func hookHash(event: String, command: String) -> String { sha("\(event)|\(command)") }
}

/// SHA-1, written out because CryptoKit is Apple-only and ReinsCore stays portable. Used for identity only, not for security.
enum Sha1 {
    static func digest(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x6745_2301, h1: UInt32 = 0xEFCD_AB89, h2: UInt32 = 0x98BA_DCFE, h3: UInt32 = 0x1032_5476, h4: UInt32 = 0xC3D2_E1F0
        var data = message
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        let bits = UInt64(message.count) * 8
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8((bits >> UInt64(shift)) & 0xFF)) }

        func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
        var w = [UInt32](repeating: 0, count: 80)
        for block in stride(from: 0, to: data.count, by: 64) {
            for i in 0..<16 {
                let o = block + i * 4
                w[i] = UInt32(data[o]) << 24 | UInt32(data[o + 1]) << 16 | UInt32(data[o + 2]) << 8 | UInt32(data[o + 3])
            }
            for i in 16..<80 { w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1) }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32, k: UInt32
                switch i {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A82_7999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9_EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1B_BCDC
                default: f = b ^ c ^ d; k = 0xCA62_C1D6
                }
                let t = rotl(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = rotl(b, 30); b = a; a = t
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d; h4 = h4 &+ e
        }
        var out: [UInt8] = []
        for h in [h0, h1, h2, h3, h4] { for shift in stride(from: 24, through: 0, by: -8) { out.append(UInt8((h >> UInt32(shift)) & 0xFF)) } }
        return out
    }
}
