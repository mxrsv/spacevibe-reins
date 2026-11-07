// Package textjs ports Sources/ReinsCore/ActivityText.swift (ActivityText and
// OrderedMap): string, path and time helpers that behave like the JavaScript the
// Node core used, so output matches the goldens byte for byte.
//
// JavaScript text semantics (plan trap "JS text semantics"):
//   - White space is the JavaScript set (U+FEFF counts, U+0085 does not), never
//     unicode.IsSpace, strings.TrimSpace or strings.Fields.
//   - Lengths, slices and sort order count UTF-16 code units. A cut inside a
//     surrogate pair drops the half pair (JavaScript would keep a lone surrogate).
//
// A Swift String is always valid Unicode; a Go string is arbitrary bytes. Every
// function here first repairs its input the way Swift's String(decoding:as:)
// does: each maximal invalid subpart becomes one U+FFFD (one UTF-16 unit). A
// lone surrogate half in WTF-8 (ED A0..BF xx) is three invalid subparts, so three
// U+FFFD. Results are always valid UTF-8.
//
// Known difference: Swift String equality and Dictionary keys use canonical
// equivalence, so OrderedMap and basename/dirname there treat NFC and NFD forms
// of one name as the same; Go compares bytes (plan H14).
package textjs
