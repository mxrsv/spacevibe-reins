import Foundation

/// String, time and hash helpers that behave like the JavaScript the Node core used (core/activity-fold.mjs and friends),
/// so the Swift output matches the goldens byte for byte: `\s` and `trim()` use the JavaScript white-space set, lengths and
/// slices count UTF-16 code units, and ids are the first 12 hex digits of SHA-1.
enum ActivityText {
    // MARK: White space

    /// The characters JavaScript treats as white space in `\s` and `String.prototype.trim`.
    static func isJSSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        default: return false
        }
    }

    /// `s.replace(/\s+/g, ' ').trim()`
    static func squash(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in s.unicodeScalars {
            if isJSSpace(scalar) {
                pendingSpace = true
            } else {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// `s.replace(/\s+/g, ' ')` without the trim.
    static func collapse(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var inSpace = false
        for scalar in s.unicodeScalars {
            if isJSSpace(scalar) {
                if !inSpace { out.append(" ") }
                inSpace = true
            } else {
                inSpace = false
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// `s.trim()`
    static func trim(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, isJSSpace(scalars[start]) { start += 1 }
        while end > start, isJSSpace(scalars[end - 1]) { end -= 1 }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars[start..<end])
        return String(out)
    }

    /// `s.slice(0, n)` by UTF-16 code units. A cut inside a surrogate pair drops the half pair (JavaScript would keep a lone surrogate).
    static func prefix(_ s: String, _ n: Int) -> String {
        let units = Array(s.utf16)
        if units.count <= n { return s }
        var end = max(0, n)
        if end > 0, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
        return String(decoding: units[0..<end], as: UTF16.self)
    }

    static func utf16Length(_ s: String) -> Int { s.utf16.count }

    /// `Array.prototype.sort()` on strings: UTF-16 code unit order.
    static func sortedStrings<S: Sequence>(_ items: S) -> [String] where S.Element == String {
        items.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    // MARK: Paths

    /// Node's `path.basename` on POSIX.
    static func basename(_ path: String) -> String {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        if trimmed == "/" { return "" }
        if let slash = trimmed.lastIndex(of: "/") { return String(trimmed[trimmed.index(after: slash)...]) }
        return String(trimmed)
    }

    static func dirname(_ path: String) -> String {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        guard let slash = trimmed.lastIndex(of: "/") else { return "." }
        if slash == trimmed.startIndex { return "/" }
        return String(trimmed[..<slash])
    }

    // MARK: Time

    /// `new Date(ms).toISOString()`: `2026-11-02T12:00:00.000Z`.
    static func isoString(_ ms: Double) -> String {
        let whole = Int64(ms.rounded(.towardZero))
        var days = whole / 86_400_000
        var rest = whole % 86_400_000
        if rest < 0 { rest += 86_400_000; days -= 1 }
        let (year, month, day) = civil(fromDays: days)
        let hour = rest / 3_600_000
        let minute = rest % 3_600_000 / 60_000
        let second = rest % 60_000 / 1000
        let milli = rest % 1000
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", year, month, day, hour, minute, second, milli)
    }

    /// `new Date(ms).toISOString().slice(0, 10)`
    static func isoDay(_ ms: Double) -> String { String(isoString(ms).prefix(10)) }

    /// Days since 1970-01-01 to a civil date (proleptic Gregorian).
    private static func civil(fromDays days: Int64) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        return (Int(year), Int(month), Int(day))
    }

    private static func days(fromCivil year: Int, _ month: Int, _ day: Int) -> Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let m = Int64(month)
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + Int64(day) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// `Date.parse` for the ISO timestamps the CLIs write: `2026-11-02T11:00:00.000Z`, with or without fraction, and `+hh:mm`
    /// offsets. A time without a zone is read as UTC (JavaScript reads it as local time). Returns nil when it does not parse.
    static func parseTimestamp(_ text: String) -> Double? {
        let b = Array(text.utf8)
        var i = 0
        func digits(_ count: Int) -> Int? {
            guard i + count <= b.count else { return nil }
            var value = 0
            for k in 0..<count {
                let c = b[i + k]
                guard c >= 0x30, c <= 0x39 else { return nil }
                value = value * 10 + Int(c - 0x30)
            }
            i += count
            return value
        }
        func take(_ c: UInt8) -> Bool {
            if i < b.count, b[i] == c { i += 1; return true }
            return false
        }
        guard let year = digits(4), take(0x2D), let month = digits(2), take(0x2D), let day = digits(2) else { return nil }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var ms = Double(days(fromCivil: year, month, day)) * 86_400_000
        if i == b.count { return ms }
        guard take(0x54) || take(0x20) else { return nil }
        guard let hour = digits(2), take(0x3A), let minute = digits(2) else { return nil }
        var second = 0
        var fraction = 0.0
        if take(0x3A) {
            guard let s = digits(2) else { return nil }
            second = s
            if take(0x2E) {
                var scale = 100.0
                var any = false
                while i < b.count, b[i] >= 0x30, b[i] <= 0x39 {
                    if scale >= 1 { fraction += Double(b[i] - 0x30) * scale }
                    scale /= 10
                    i += 1
                    any = true
                }
                guard any else { return nil }
            }
        }
        guard hour <= 24, minute < 60, second < 60 else { return nil }
        ms += Double(hour * 3_600_000 + minute * 60_000 + second * 1000) + fraction.rounded(.down)
        if take(0x5A) { return i == b.count ? ms : nil }
        if i < b.count, b[i] == 0x2B || b[i] == 0x2D {
            let sign: Double = b[i] == 0x2D ? -1 : 1
            i += 1
            guard let oh = digits(2) else { return nil }
            _ = take(0x3A)
            guard let om = digits(2), i == b.count else { return nil }
            return ms - sign * Double(oh * 3_600_000 + om * 60_000)
        }
        return i == b.count ? ms : nil
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// `Date.parse(`${text} UTC`)` for a `ps -o lstart=` value such as `Mon Nov  2 11:58:00 2026` (printed with TZ=UTC).
    static func parseProcessStart(_ text: String?) -> Double? {
        guard let text else { return nil }
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count == 5, let month = months.firstIndex(of: parts[1]), let day = Int(parts[2]), let year = Int(parts[4]) else { return nil }
        let clock = parts[3].split(separator: ":").compactMap { Int($0) }
        guard clock.count == 3 else { return nil }
        let ms = Double(days(fromCivil: year, month + 1, day)) * 86_400_000 + Double(clock[0] * 3_600_000 + clock[1] * 60_000 + clock[2] * 1000)
        return ms == 0 ? nil : ms
    }

    // MARK: Hash

    /// First 12 hex digits of SHA-1: `sha()` in core/inventory.mjs. Used for failure keys and hook hashes, never for security.
    static func sha12(_ text: String) -> String {
        String(sha1Hex(Array(text.utf8)).prefix(12))
    }

    static func sha1Hex(_ input: [UInt8]) -> String {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0
        var message = input
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }
        var w = [UInt32](repeating: 0, count: 80)
        func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for t in 0..<16 {
                let o = chunk + t * 4
                w[t] = UInt32(message[o]) << 24 | UInt32(message[o + 1]) << 16 | UInt32(message[o + 2]) << 8 | UInt32(message[o + 3])
            }
            for t in 16..<80 { w[t] = rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1) }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for t in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch t {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
                default: f = b ^ c ^ d; k = 0xCA62C1D6
                }
                let temp = rotl(a, 5) &+ f &+ e &+ k &+ w[t]
                e = d; d = c; c = rotl(b, 30); b = a; a = temp
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d; h4 = h4 &+ e
        }
        return [h0, h1, h2, h3, h4].map { String(format: "%08x", $0) }.joined()
    }

    // MARK: Byte search

    /// True when `needle` occurs in `haystack`. The log lines are searched as bytes, as the Node code searched strings.
    static func contains(_ haystack: Data, _ needle: StaticString) -> Bool {
        needle.withUTF8Buffer { n in
            haystack.withUnsafeBytes { h in
                guard n.count > 0, h.count >= n.count, let hp = h.baseAddress, let np = n.baseAddress else { return n.count == 0 }
                return memmem(hp, h.count, np, n.count) != nil
            }
        }
    }

    /// The `[^"]+` values that follow every `"tool_use_id":"` in a line.
    static func toolUseIds(in line: Data) -> [String] {
        let key = Array("\"tool_use_id\":\"".utf8)
        let bytes = [UInt8](line)
        var out: [String] = []
        var i = 0
        while i + key.count <= bytes.count {
            if bytes[i] == key[0], bytes[i..<(i + key.count)].elementsEqual(key) {
                let start = i + key.count
                var end = start
                while end < bytes.count, bytes[end] != 0x22 { end += 1 }
                if end > start, end < bytes.count { out.append(String(decoding: bytes[start..<end], as: UTF8.self)) }
                i = max(end, i + 1)
            } else {
                i += 1
            }
        }
        return out
    }
}

/// A dictionary that remembers insertion order, like a JavaScript `Map` (a repeated `set` keeps the first position).
struct OrderedMap<Value> {
    private(set) var keys: [String] = []
    private var storage: [String: Value] = [:]

    var isEmpty: Bool { keys.isEmpty }
    var count: Int { keys.count }
    var values: [Value] { keys.compactMap { storage[$0] } }
    var entries: [(key: String, value: Value)] { keys.compactMap { key in storage[key].map { (key, $0) } } }
    var last: Value? { keys.last.flatMap { storage[$0] } }

    subscript(key: String) -> Value? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = newValue
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    mutating func removeAll() {
        keys.removeAll()
        storage.removeAll()
    }
}
