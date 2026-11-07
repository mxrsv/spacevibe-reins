package ojson

import (
	"os"
	"strings"
	"testing"
)

const settingsFixture = "../../testdata/fixtures/home/.claude/settings.json"

func mustDoc(t *testing.T, text string) *Document {
	t.Helper()
	d, err := ParseString(text)
	if err != nil {
		t.Fatalf("ParseString(%q): %v", text, err)
	}
	return d
}

func mustValue(t *testing.T, d *Document, path ...Step) Value {
	t.Helper()
	v, ok := d.Get(path...)
	if !ok {
		t.Fatalf("path %v not found", path)
	}
	return v
}

// Swift: OrderedJSONTests.swift "an unmodified document is written back as the same bytes" (11 arguments)
func TestRoundTripKeepsEveryByte(t *testing.T) {
	samples := []struct{ name, text string }{
		{"two spaces, trailing newline", "{\n  \"b\": 1,\n  \"a\": [\n    true,\n    null\n  ]\n}\n"},
		{"tabs, no trailing newline", "{\n\t\"b\": {\n\t\t\"c\": \"x\"\n\t}\n}"},
		{"four spaces", "{\n    \"z\": 1,\n    \"y\": 2\n}\n"},
		{"CRLF", "{\r\n  \"a\": 1,\r\n  \"b\": [\r\n    2\r\n  ]\r\n}\r\n"},
		{"minified", "{\"a\":1,\"b\":[1,2,{\"c\":null}]}"},
		{"odd spacing", "{ \"a\" :1 ,\n\n  \"b\"  : [ 1 ,2 ]   }  \n\n"},
		{"numbers keep their text", "[1.0, 1e3, -0, 0.50, 1E+2, 12345678901234567890]"},
		{"escapes and unicode", "{\"é\":\"\\u00e9 \\ud83d\\ude42 🙂 \\n \\/ \\\\ \\\"\",\"k\":\"\\ud800\"}"},
		{"scalar root", "  \"just a string\"\n"},
		{"empty containers", "{\"a\":{},\"b\":[],\"c\":[ ],\"d\":{ }}"},
		{"duplicate keys", "{\"a\":1,\"a\":2}"},
	}
	for _, s := range samples {
		t.Run(s.name, func(t *testing.T) {
			d := mustDoc(t, s.text)
			if string(d.Bytes()) != s.text {
				t.Errorf("Bytes() = %q, want %q", d.Bytes(), s.text)
			}
			if d.Text() != s.text {
				t.Errorf("Text() = %q, want %q", d.Text(), s.text)
			}
		})
	}
}

// Swift: OrderedJSONTests.swift "a fixture settings file round-trips byte for byte"
func TestFixtureSettingsRoundTrip(t *testing.T) {
	original, err := os.ReadFile(settingsFixture)
	if err != nil {
		t.Fatal(err)
	}
	d, err := Parse(original)
	if err != nil {
		t.Fatal(err)
	}
	if string(d.Bytes()) != string(original) {
		t.Error("fixture settings.json did not round-trip")
	}
}

// Swift: OrderedJSONTests.swift "values parse with key order and duplicates kept"
func TestValuesKeepOrderAndDuplicates(t *testing.T) {
	d := mustDoc(t, `{"b":1,"a":[true,null,"x"],"b":2}`)
	members, ok := d.Root().ObjectValue()
	if !ok {
		t.Fatal("root is not an object")
	}
	var keys []string
	for _, m := range members {
		keys = append(keys, m.Key)
	}
	if strings.Join(keys, ",") != "b,a,b" {
		t.Errorf("keys = %v, want [b a b]", keys)
	}
	if v, _ := d.Root().Member("b"); !v.Equal(Number("2")) {
		t.Errorf(`root["b"] = %v, want 2 (last duplicate wins)`, v)
	}
	if v := mustValue(t, d, Key("a"), Index(2)); !v.Equal(String("x")) {
		t.Errorf(`["a",2] = %v`, v)
	}
	if _, ok := d.Get(Key("a"), Index(9)); ok {
		t.Error(`["a",9] must not exist`)
	}
	if _, ok := d.Get(Key("a"), Index(-1)); ok {
		t.Error(`["a",-1] must not exist`)
	}
	if _, ok := d.Get(Key("nope"), Key("deeper")); ok {
		t.Error(`["nope","deeper"] must not exist`)
	}
	if _, ok := d.Get(Key("b"), Key("deeper")); ok {
		t.Error("a key on a number must not exist")
	}
}

// Swift: OrderedJSONTests.swift "escapes decode, including surrogate pairs and a lone surrogate"
func TestEscapesDecode(t *testing.T) {
	d := mustDoc(t, `{"s":"\u00e9\ud83d\ude42\n\/","lone":"\ud800x"}`)
	if v, _ := d.Root().Member("s"); !v.Equal(String("é🙂\n/")) {
		t.Errorf(`root["s"] = %v`, v)
	}
	if v, _ := d.Root().Member("lone"); !v.Equal(String("\uFFFDx")) {
		t.Errorf(`root["lone"] = %v`, v)
	}
}

// Extra: escape corner cases the Swift parser handles in its surrogate branch.
func TestEscapeCornerCases(t *testing.T) {
	cases := []struct{ name, json, want string }{
		{"lone low surrogate", `"\udc00"`, "\uFFFD"},
		{"high then non-surrogate escape", `"\ud800\u0041"`, "\uFFFDA"},
		{"high then high then low", `"\ud800\ud83d\ude42"`, "\uFFFD🙂"},
		{"high then plain text", `"\ud83dab"`, "\uFFFDab"},
		{"nul escape", `"\u0000"`, "\x00"},
		{"upper-case hex", `"\u00E9"`, "é"},
		{"every simple escape", `"\"\\\/\b\f\n\r\t"`, "\"\\/\b\f\n\r\t"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d := mustDoc(t, c.json)
			if got, _ := d.Root().StringValue(); got != c.want {
				t.Errorf("got %q, want %q", got, c.want)
			}
			if d.Text() != c.json {
				t.Error("bytes changed")
			}
		})
	}
}

// Extra: number text is kept byte for byte, never routed through a float.
func TestNumberTextIsExact(t *testing.T) {
	d := mustDoc(t, "[1.0, 1e3, -0, 0.50, 1E+2, 12345678901234567890, 1.7976931348623157e309, -0.0e-0]")
	items, _ := d.Root().ArrayValue()
	want := []string{"1.0", "1e3", "-0", "0.50", "1E+2", "12345678901234567890", "1.7976931348623157e309", "-0.0e-0"}
	if len(items) != len(want) {
		t.Fatalf("got %d items", len(items))
	}
	for i, w := range want {
		if got, _ := items[i].NumberText(); got != w {
			t.Errorf("item %d = %q, want %q", i, got, w)
		}
	}
}

// Extra: a document is immutable, and Bytes returns a copy.
func TestDocumentIsImmutable(t *testing.T) {
	src := []byte(`{"a":1}`)
	d, err := Parse(src)
	if err != nil {
		t.Fatal(err)
	}
	src[2] = 'z'
	b := d.Bytes()
	b[2] = 'y'
	if d.Text() != `{"a":1}` {
		t.Errorf("document changed through its inputs: %q", d.Text())
	}
	if _, err := d.Set(Path("a"), Int(2)); err != nil {
		t.Fatal(err)
	}
	if d.Text() != `{"a":1}` || !mustValue(t, d, Key("a")).Equal(Int(1)) {
		t.Error("an edit changed the original document")
	}
}

func TestValueEqual(t *testing.T) {
	a := Object(Member{"k", Array(Int(1), String("x"), Null(), Bool(true))})
	b := Object(Member{"k", Array(Int(1), String("x"), Null(), Bool(true))})
	if !a.Equal(b) {
		t.Error("equal values reported different")
	}
	for _, other := range []Value{
		Object(Member{"k", Array(Int(1), String("x"), Null(), Bool(false))}),
		Object(Member{"j", Array(Int(1), String("x"), Null(), Bool(true))}),
		Object(Member{"k", Array(Int(1))}),
		Object(),
		Number("1.0"),
	} {
		if a.Equal(other) {
			t.Errorf("%v should differ", other)
		}
	}
	if Number("1").Equal(Number("1.0")) {
		t.Error("numbers compare by text")
	}
}
