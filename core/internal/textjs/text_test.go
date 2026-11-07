package textjs

import (
	"slices"
	"testing"
)

func TestIsJSSpace(t *testing.T) {
	// The JavaScript set; U+0085 and U+180E and U+200B are not in it, U+FEFF is.
	yes := []rune{0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x2005, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF}
	no := []rune{0x00, 0x08, 0x0E, 0x1F, 0x21, 0x85, 0x180E, 0x200B, 0x200C, 0x200D, 0x2060, 0x2027, 0x202A, 0x3001, 0xFEFE, 0xFFFD, 0x1F600}
	for _, r := range yes {
		if !IsJSSpace(r) {
			t.Errorf("U+%04X should be JS white space", r)
		}
	}
	for _, r := range no {
		if IsJSSpace(r) {
			t.Errorf("U+%04X should not be JS white space", r)
		}
	}
}

func TestRepair(t *testing.T) {
	// Expected values come from Swift String(decoding:as:) (maximal subpart replacement).
	cases := []struct{ name, in, want string }{
		{"valid", "aé\U0001F600", "aé\U0001F600"},
		{"truncated 3-byte", "\xE2\x82", "�"},
		{"WTF-8 lone high surrogate", "\xED\xA0\x80", "���"},
		{"WTF-8 lone low surrogate", "\xED\xBF\xBF", "���"},
		{"truncated 4-byte", "\xF0\x9F\x98", "�"},
		{"overlong C0 80", "\xC0\x80", "��"},
		{"FF", "\xFF", "�"},
		{"above U+10FFFF", "\xF4\x90\x80\x80", "����"},
		{"overlong E0 80 80", "\xE0\x80\x80", "���"},
		{"F0 80", "\xF0\x80", "��"},
		{"truncated inside text", "a\xE2\x82a", "a�a"},
		{"lead then ASCII", "\xF0\x9F\x98A", "�A"},
		{"stray continuation bytes", "\x80\x80", "��"},
		{"E0 A0 truncated", "\xE0\xA0", "�"},
		{"F4 8F BF truncated", "\xF4\x8F\xBF", "�"},
		{"lone C3", "\xC3", "�"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := Repair(c.in); got != c.want {
				t.Errorf("Repair(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

func TestSquash(t *testing.T) {
	cases := []struct{ name, in, want string }{
		// Swift: ActivityTests.swift "text helpers behave like the JavaScript they replace"
		{"swift vector", "  a \t\n b c  ", "a b c"},
		{"empty", "", ""},
		{"only space", " \t \uFEFF  ", ""},
		{"U+0085 is not space", "\u0085a\uFEFF  b​c᠎ ", "\u0085a b​c᠎"},
		{"BOM inside", "a\uFEFFb", "a b"},
		{"astral kept", "  \U0001F600 \U0001D11E  ", "\U0001F600 \U0001D11E"},
		{"lone surrogate half becomes U+FFFD", "a\xED\xA0\x80 b", "a��� b"},
		{"invalid byte between spaces", " \xFF ", "�"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := Squash(c.in); got != c.want {
				t.Errorf("Squash(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

func TestCollapse(t *testing.T) {
	cases := []struct{ name, in, want string }{
		{"keeps edges as one space", "\uFEFF a \u0085  b　", " a \u0085 b "},
		{"empty", "", ""},
		{"runs", "a \t\n\r b", "a b"},
		{"newline pair", "x\r\ny", "x y"},
		{"astral", "\U0001F600  \U0001F600", "\U0001F600 \U0001F600"},
		{"invalid byte", "a \xFF  b", "a � b"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := Collapse(c.in); got != c.want {
				t.Errorf("Collapse(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

func TestTrim(t *testing.T) {
	cases := []struct{ name, in, want string }{
		// Swift: MutateTests.swift "JavaScript trim and whitespace collapse"
		{"nbsp and BOM", "  a b \uFEFF\n", "a b"},
		{"zero-width space stays", " ​x", "​x"},
		{"U+0085 stays", "\u0085\uFEFFx ", "\u0085\uFEFFx"},
		{"empty", "", ""},
		{"all space", "\uFEFF 　", ""},
		{"astral edges", " \U0001F600 ", "\U0001F600"},
		{"half surrogate at the edge", "\xED\xA0\x80 ", "���"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := Trim(c.in); got != c.want {
				t.Errorf("Trim(%q) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

func TestPrefix(t *testing.T) {
	cases := []struct {
		name, in string
		n        int
		want     string
	}{
		// Swift: ActivityTests.swift "text helpers behave like the JavaScript they replace"
		{"swift vector", "héllo", 2, "hé"},
		{"fits", "abc", 3, "abc"},
		{"longer than the string", "abc", 10, "abc"},
		{"empty", "", 0, ""},
		{"zero", "abc", 0, ""},
		{"negative", "abc", -1, ""},
		{"cut before pair", "a\U0001F600b", 1, "a"},
		{"cut inside pair drops the half", "a\U0001F600b", 2, "a"},
		{"cut after pair", "a\U0001F600b", 3, "a\U0001F600"},
		{"pair first, n=1", "\U0001F600", 1, ""},
		{"pair first, n=0", "\U0001F600", 0, ""},
		{"pair first, n=2", "\U0001F600", 2, "\U0001F600"},
		{"two pairs, n=3 drops the second", "\U0001F600\U0001F600", 3, "\U0001F600"},
		{"BMP three-byte is one unit", "€€€", 2, "€€"},
		{"invalid byte is one unit", "\xFFab", 2, "�a"},
		{"WTF-8 half is three units", "\xED\xA0\x80z", 2, "��"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := Prefix(c.in, c.n); got != c.want {
				t.Errorf("Prefix(%q, %d) = %q, want %q", c.in, c.n, got, c.want)
			}
		})
	}
}

func TestUTF16Length(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"abc", 3},
		{"héllo", 5},
		{"€", 1},
		{"\U0001F600", 2},
		{"a\U0001D11Eb", 4},
		{"\uFEFF\u0085", 2},
		{"\xFF", 1},
		{"\xED\xA0\x80", 3},
	}
	for _, c := range cases {
		if got := UTF16Length(c.in); got != c.want {
			t.Errorf("UTF16Length(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestSortedStrings(t *testing.T) {
	// Expected order from Swift utf16.lexicographicallyPrecedes: astral (D800..) sorts before U+E000..U+FFFF.
	in := []string{"～", "\U0001F600", "", "a", "", "ab", "\U00010000", "￿", "\U0001D11E", "\U0001F601", "Z", "z", "é", "é"}
	want := []string{"", "Z", "a", "ab", "é", "z", "é", "\U00010000", "\U0001D11E", "\U0001F600", "\U0001F601", "", "～", "￿"}
	orig := slices.Clone(in)
	got := SortedStrings(in)
	if !slices.Equal(got, want) {
		t.Errorf("SortedStrings = %q, want %q", got, want)
	}
	if !slices.Equal(in, orig) {
		t.Errorf("SortedStrings changed its input: %q", in)
	}
	if got := SortedStrings(nil); len(got) != 0 {
		t.Errorf("SortedStrings(nil) = %q", got)
	}
	// Byte order would put U+FFFF before U+10000; UTF-16 order does not.
	if got := SortedStrings([]string{"￿", "\U00010000"}); got[0] != "\U00010000" {
		t.Errorf("astral must sort before U+FFFF, got %q", got)
	}
	// Same high surrogate, different low surrogate.
	if got := SortedStrings([]string{"\U0001F601", "\U0001F600"}); got[0] != "\U0001F600" {
		t.Errorf("got %q", got)
	}
	// A prefix sorts first.
	if got := SortedStrings([]string{"ab", "a"}); got[0] != "a" {
		t.Errorf("got %q", got)
	}
}

func TestSortedStringsRepairsInvalidBytes(t *testing.T) {
	got := SortedStrings([]string{"b", "\xFF"})
	if !slices.Equal(got, []string{"b", "�"}) {
		// U+FFFD (0xFFFD) sorts after 'b'.
		t.Errorf("got %q", got)
	}
}
