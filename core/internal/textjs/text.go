package textjs

import (
	"slices"
	"strings"
	"unicode/utf8"
)

// IsJSSpace reports whether r is white space for JavaScript's \s and String.prototype.trim.
func IsJSSpace(r rune) bool {
	switch {
	case r >= 0x09 && r <= 0x0D, r == 0x20, r == 0xA0, r == 0x1680,
		r >= 0x2000 && r <= 0x200A, r == 0x2028, r == 0x2029, r == 0x202F, r == 0x205F, r == 0x3000, r == 0xFEFF:
		return true
	}
	return false
}

// Repair returns s with each maximal invalid UTF-8 subpart replaced by one U+FFFD,
// the way Swift's String(decoding: bytes, as: UTF8.self) does.
func Repair(s string) string {
	if utf8.ValidString(s) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		if r == utf8.RuneError && size <= 1 {
			size = invalidSubpartLen(s[i:])
		}
		b.WriteRune(r)
		i += size
	}
	return b.String()
}

// invalidSubpartLen is the length of the maximal subpart of an ill-formed sequence at the start of s
// (Unicode 15 section 3.9, Table 3-7).
func invalidSubpartLen(s string) int {
	lead := s[0]
	var total int
	lo, hi := byte(0x80), byte(0xBF)
	switch {
	case lead >= 0xC2 && lead <= 0xDF:
		total = 2
	case lead == 0xE0:
		total, lo = 3, 0xA0
	case lead >= 0xE1 && lead <= 0xEF:
		total = 3
		if lead == 0xED {
			hi = 0x9F
		}
	case lead == 0xF0:
		total, lo = 4, 0x90
	case lead >= 0xF1 && lead <= 0xF3:
		total = 4
	case lead == 0xF4:
		total, hi = 4, 0x8F
	default:
		return 1
	}
	n := 1
	for n < total && n < len(s) {
		c := s[n]
		if c < lo || c > hi {
			break
		}
		lo, hi = 0x80, 0xBF
		n++
	}
	return n
}

// utf16Units is the number of UTF-16 code units r takes.
func utf16Units(r rune) int {
	if r >= 0x10000 {
		return 2
	}
	return 1
}

// Squash is s.replace(/\s+/g, ' ').trim().
func Squash(s string) string {
	var out strings.Builder
	pendingSpace := false
	for _, r := range Repair(s) {
		if IsJSSpace(r) {
			pendingSpace = true
			continue
		}
		if pendingSpace && out.Len() > 0 {
			out.WriteByte(' ')
		}
		pendingSpace = false
		out.WriteRune(r)
	}
	return out.String()
}

// Collapse is s.replace(/\s+/g, ' ') without the trim.
func Collapse(s string) string {
	var out strings.Builder
	inSpace := false
	for _, r := range Repair(s) {
		if IsJSSpace(r) {
			if !inSpace {
				out.WriteByte(' ')
			}
			inSpace = true
			continue
		}
		inSpace = false
		out.WriteRune(r)
	}
	return out.String()
}

// Trim is s.trim().
func Trim(s string) string {
	return strings.TrimFunc(Repair(s), IsJSSpace)
}

// Prefix is s.slice(0, n) by UTF-16 code units. A cut inside a surrogate pair drops
// the half pair. A negative n gives "".
func Prefix(s string, n int) string {
	s = Repair(s)
	used := 0
	for i, r := range s {
		w := utf16Units(r)
		if used+w > n {
			return s[:i]
		}
		used += w
	}
	return s
}

// UTF16Length is s.length: the number of UTF-16 code units.
func UTF16Length(s string) int {
	n := 0
	for _, r := range Repair(s) {
		n += utf16Units(r)
	}
	return n
}

// SortedStrings is Array.prototype.sort() on strings: UTF-16 code unit order. It
// returns a new slice and leaves items alone.
func SortedStrings(items []string) []string {
	out := make([]string, len(items))
	for i, s := range items {
		out[i] = Repair(s)
	}
	slices.SortFunc(out, compareUTF16)
	return out
}

// compareUTF16 orders two valid strings by UTF-16 code units.
func compareUTF16(a, b string) int {
	for a != "" && b != "" {
		ra, sa := utf8.DecodeRuneInString(a)
		rb, sb := utf8.DecodeRuneInString(b)
		if ra != rb {
			ua, ub := firstUnit(ra), firstUnit(rb)
			if ua != ub {
				return int(ua) - int(ub)
			}
			// Same high surrogate, different astral runes: the low surrogates differ.
			return int(ra) - int(rb)
		}
		a, b = a[sa:], b[sb:]
	}
	return len(a) - len(b)
}

// firstUnit is the first UTF-16 code unit of r.
func firstUnit(r rune) rune {
	if r >= 0x10000 {
		return 0xD800 + (r-0x10000)>>10
	}
	return r
}
