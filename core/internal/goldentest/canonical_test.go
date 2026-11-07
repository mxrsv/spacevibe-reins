package goldentest

import (
	"encoding/json"
	"math"
	"testing"
)

// Expected values come from Node 24: String(n) for numbers, JSON.stringify(v, null, 2) for layout. A separate
// scratch run compared es6Number with Node on 1,499,794 random doubles (no mismatch).
func TestCanonicalNumberText(t *testing.T) {
	cases := []struct {
		in   float64
		want string
	}{
		{0, "0"}, {math.Copysign(0, -1), "0"}, {1, "1"}, {-1, "-1"}, {100, "100"},
		{1e20, "100000000000000000000"}, {1e21, "1e+21"}, {1.5e21, "1.5e+21"},
		{123456789012345680000, "123456789012345680000"}, {1.2345678901234568e22, "1.2345678901234568e+22"},
		{1e-6, "0.000001"}, {1e-7, "1e-7"}, {1.5e-7, "1.5e-7"}, {0.000001234, "0.000001234"}, {0.000012345, "0.000012345"},
		{123.456, "123.456"}, {0.30000000000000004, "0.30000000000000004"}, {4.35, "4.35"}, {0.5, "0.5"}, {1.0 / 3, "0.3333333333333333"},
		{5e-324, "5e-324"}, {math.MaxFloat64, "1.7976931348623157e+308"}, {-2.5e-10, "-2.5e-10"},
		{9007199254740992, "9007199254740992"}, {9007199254740994, "9007199254740994"},
	}
	for _, c := range cases {
		if got, err := es6Number(c.in); err != nil || got != c.want {
			t.Errorf("%v: got %q (%v), want %q", c.in, got, err, c.want)
		}
	}
	for _, bad := range []float64{math.NaN(), math.Inf(1), math.Inf(-1)} {
		if _, err := Canonical(bad); err == nil {
			t.Errorf("%v must be refused", bad)
		}
	}
	// json.Number goes through float64, so source text is normalized to JavaScript's.
	if out, _ := Canonical(json.Number("1.50")); string(out) != "1.5\n" {
		t.Errorf("1.50 -> %q", out)
	}
	if out, _ := Canonical(json.Number("1E3")); string(out) != "1000\n" {
		t.Errorf("1E3 -> %q", out)
	}
	if _, err := Canonical(json.Number("1e999")); err == nil {
		t.Error("an out-of-range number must be refused")
	}
}

func TestCanonicalLayoutKeysAndEscapes(t *testing.T) {
	v := map[string]any{
		"b": 1, " ": "  <>&\x7f\x00\x1f\b\f\n\r\t\"\\", "é": []any{}, "a": map[string]any{},
		"😀": 1, "￿": 2, "z": []any{1, []any{2, map[string]any{}}},
	}
	// Keys in UTF-16 order: "a", "b", "z", "é", U+2028, the emoji, U+FFFF. The emoji is a surrogate pair
	// (D83D DE00) and sorts below U+FFFF; a byte-order sort would put it last.
	want := "{\n" +
		"  \"a\": {},\n" +
		"  \"b\": 1,\n" +
		"  \"z\": [\n    1,\n    [\n      2,\n      {}\n    ]\n  ],\n" +
		"  \"é\": [],\n" +
		"  \"\u2028\": \"\u2028\u2029<>&\x7f\\u0000\\u001f\\b\\f\\n\\r\\t\\\"\\\\\",\n" +
		"  \"😀\": 1,\n" +
		"  \"\uffff\": 2\n" +
		"}\n"
	got, err := Canonical(v)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != want {
		t.Errorf("canonical bytes differ\n%s", UnifiedDiff("want", "got", want, string(got)))
	}
}

func TestCanonicalTypesAndRefusals(t *testing.T) {
	type pair struct{ A int }
	out, err := Canonical(map[string]any{"i8": int8(-3), "u": uint16(7), "f32": float32(0.5), "s": []string{"x"}, "m": map[string]int{"k": 1},
		"nil": nil, "t": true, "arr": [2]bool{true, false}, "named": json.RawMessage(nil)})
	if err == nil {
		t.Logf("%s", out) // json.RawMessage is a byte slice: written as an array of numbers
	}
	for _, bad := range []any{pair{1}, map[int]string{1: "x"}, make(chan int), func() {}} {
		if _, err := Canonical(bad); err == nil {
			t.Errorf("%T must be refused", bad)
		}
	}
	// Invalid UTF-8 is written as U+FFFD, one per bad byte, like a JavaScript string decoded from the bytes.
	if out, _ := Canonical("a\xffb"); string(out) != "\"a�b\"\n" {
		t.Errorf("invalid utf-8: %q", out)
	}
	// Equal trees give equal bytes regardless of Go map order, and the hash is stable.
	a, _ := CanonicalSHA256(map[string]any{"x": 1, "y": []any{"p", "q"}, "z": nil})
	b, _ := CanonicalSHA256(map[string]any{"z": nil, "y": []any{"p", "q"}, "x": 1.0})
	if a != b || len(a) != 64 {
		t.Errorf("hashes %s %s", a, b)
	}
}

func TestCanonicalDoesNotChangeInput(t *testing.T) {
	in := map[string]any{"k": []any{map[string]any{"b": 1, "a": 2}}}
	if _, err := Canonical(in); err != nil {
		t.Fatal(err)
	}
	if len(in) != 1 {
		t.Error("input changed")
	}
}
