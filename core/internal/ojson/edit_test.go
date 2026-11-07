package ojson

import (
	"bytes"
	"encoding/json"
	"errors"
	"testing"
	"unicode/utf8"
)

func mustSet(t *testing.T, d *Document, path []Step, v Value) *Document {
	t.Helper()
	out, err := d.Set(path, v)
	if err != nil {
		t.Fatalf("Set(%v): %v", path, err)
	}
	return out
}

func mustAppend(t *testing.T, d *Document, v Value, path []Step) *Document {
	t.Helper()
	out, err := d.Append(v, path)
	if err != nil {
		t.Fatalf("Append(%v): %v", path, err)
	}
	return out
}

func mustRemove(t *testing.T, d *Document, path []Step) *Document {
	t.Helper()
	out, err := d.Remove(path)
	if err != nil {
		t.Fatalf("Remove(%v): %v", path, err)
	}
	return out
}

func expectText(t *testing.T, d *Document, want string) {
	t.Helper()
	if d.Text() != want {
		t.Errorf("got  %q\nwant %q", d.Text(), want)
	}
	if !json.Valid(d.Bytes()) {
		t.Errorf("result is not valid JSON: %q", d.Text())
	}
}

// Swift: OrderedJSONTests.swift "replacing a value touches only that value"
func TestReplaceInPlace(t *testing.T) {
	source := "{\n  \"a\": 1,\n  \"model\": \"old\",\n  \"z\": [1, 2]\n}\n"
	expectText(t, mustSet(t, mustDoc(t, source), Path("model"), String("new")),
		"{\n  \"a\": 1,\n  \"model\": \"new\",\n  \"z\": [1, 2]\n}\n")
	expectText(t, mustSet(t, mustDoc(t, source), Path("z", 1), Int(20)),
		"{\n  \"a\": 1,\n  \"model\": \"old\",\n  \"z\": [1, 20]\n}\n")
}

// Swift: OrderedJSONTests.swift "a new key goes at the end, in the document's indent"
func TestAddKeyInDocumentStyle(t *testing.T) {
	cases := []struct {
		name, source string
		value        Value
		want         string
	}{
		{"two spaces", "{\n  \"a\": 1\n}\n", Bool(true), "{\n  \"a\": 1,\n  \"b\": true\n}\n"},
		{"tab", "{\n\t\"a\": 1\n}", String("x"), "{\n\t\"a\": 1,\n\t\"b\": \"x\"\n}"},
		{"CRLF four spaces", "{\r\n    \"a\": 1\r\n}\r\n", Int(2), "{\r\n    \"a\": 1,\r\n    \"b\": 2\r\n}\r\n"},
		{"minified", `{"a":1}`, Int(2), `{"a":1,"b":2}`},
		{"spaced inline", `{ "a": 1 }`, Int(2), `{ "a": 1, "b": 2 }`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			expectText(t, mustSet(t, mustDoc(t, c.source), Path("b"), c.value), c.want)
		})
	}
}

// Swift: OrderedJSONTests.swift "missing parents are created as nested objects"
func TestMissingParentsAreCreated(t *testing.T) {
	expectText(t, mustSet(t, mustDoc(t, "{\n  \"a\": 1\n}\n"), Path("permissions", "defaultMode"), String("plan")),
		"{\n  \"a\": 1,\n  \"permissions\": {\n    \"defaultMode\": \"plan\"\n  }\n}\n")
	expectText(t, mustSet(t, mustDoc(t, "{}\n"), Path("a", "b"), Int(1)), "{\n  \"a\": {\n    \"b\": 1\n  }\n}\n")
	expectText(t, mustSet(t, mustDoc(t, "{}"), Path("a"), Int(1)), `{"a":1}`)
}

// Swift: OrderedJSONTests.swift "appending to an array: multi-line, inline, empty and missing"
func TestAppend(t *testing.T) {
	multi := "{\n  \"permissions\": {\n    \"allow\": [\n      \"Read\",\n      \"Edit\"\n    ]\n  }\n}\n"
	expectText(t, mustAppend(t, mustDoc(t, multi), String("Bash(git status:*)"), Path("permissions", "allow")),
		"{\n  \"permissions\": {\n    \"allow\": [\n      \"Read\",\n      \"Edit\",\n      \"Bash(git status:*)\"\n    ]\n  }\n}\n")
	expectText(t, mustAppend(t, mustDoc(t, `{"a": ["x", "y"]}`), String("z"), Path("a")), `{"a": ["x", "y", "z"]}`)
	expectText(t, mustAppend(t, mustDoc(t, `{"a":["x"]}`), String("z"), Path("a")), `{"a":["x","z"]}`)
	expectText(t, mustAppend(t, mustDoc(t, "{\n  \"a\": []\n}\n"), String("z"), Path("a")),
		"{\n  \"a\": [\n    \"z\"\n  ]\n}\n")
	expectText(t, mustAppend(t, mustDoc(t, "{\n  \"a\": 1\n}\n"), String("z"), Path("permissions", "deny")),
		"{\n  \"a\": 1,\n  \"permissions\": {\n    \"deny\": [\n      \"z\"\n    ]\n  }\n}\n")
}

// Swift: OrderedJSONTests.swift "removing keeps the commas valid wherever the member sits"
func TestRemoveKeepsCommasValid(t *testing.T) {
	source := "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3\n}\n"
	expectText(t, mustRemove(t, mustDoc(t, source), Path("a")), "{\n  \"b\": 2,\n  \"c\": 3\n}\n")
	expectText(t, mustRemove(t, mustDoc(t, source), Path("b")), "{\n  \"a\": 1,\n  \"c\": 3\n}\n")
	expectText(t, mustRemove(t, mustDoc(t, source), Path("c")), "{\n  \"a\": 1,\n  \"b\": 2\n}\n")
	expectText(t, mustRemove(t, mustDoc(t, "{\n  \"a\": 1\n}\n"), Path("a")), "{}\n")
	expectText(t, mustRemove(t, mustDoc(t, `{"a":[1,2,3]}`), Path("a", 1)), `{"a":[1,3]}`)
	expectText(t, mustRemove(t, mustDoc(t, `{"a":[1,2,3]}`), Path("a", 2)), `{"a":[1,2]}`)
	expectText(t, mustRemove(t, mustDoc(t, `{"a":[1]}`), Path("a", 0)), `{"a":[]}`)
}

// Swift: OrderedJSONTests.swift "a nested object value is written in the document's style"
func TestNestedValueInDocumentStyle(t *testing.T) {
	value := Object(Member{"type", String("command")}, Member{"args", Array(String("a"), String("b"))})
	expectText(t, mustSet(t, mustDoc(t, "{\n  \"hooks\": []\n}\n"), Path("hooks", 0), value),
		"{\n  \"hooks\": [\n    {\n      \"type\": \"command\",\n      \"args\": [\n        \"a\",\n        \"b\"\n      ]\n    }\n  ]\n}\n")
}

// Swift: OrderedJSONTests.swift "only the edited region changes: bytes before and after are identical"
func TestOnlyTheEditedRegionChanges(t *testing.T) {
	source := readFixture(t)
	before, err := Parse(source)
	if err != nil {
		t.Fatal(err)
	}
	after := mustAppend(t, before, String("Bash(echo hi:*)"), Path("permissions", "allow"))
	old, next := source, after.Bytes()
	prefix := 0
	for prefix < len(old) && prefix < len(next) && old[prefix] == next[prefix] {
		prefix++
	}
	suffix := 0
	for suffix < len(old)-prefix && suffix < len(next)-prefix && old[len(old)-1-suffix] == next[len(next)-1-suffix] {
		suffix++
	}
	changed := string(next[prefix : len(next)-suffix])
	if !bytes.Contains([]byte(changed), []byte("Bash(echo hi:*)")) {
		t.Errorf("changed region lacks the new value: %q", changed)
	}
	if n := utf8.RuneCountInString(changed); n >= 80 {
		t.Errorf("changed region is %d characters, want < 80: %q", n, changed)
	}
	for _, key := range []string{"hooks", "env"} {
		b, _ := before.Root().Member(key)
		a, _ := after.Root().Member(key)
		if !a.Equal(b) {
			t.Errorf("%q changed", key)
		}
	}
	allow := mustValue(t, after, Key("permissions"), Key("allow"))
	items, _ := allow.ArrayValue()
	if last := items[len(items)-1]; !last.Equal(String("Bash(echo hi:*)")) {
		t.Errorf("last allow entry = %v", last)
	}
}

// Extra: the same splice property on every edit kind, on a hand-made document with odd spacing.
func TestEveryEditKeepsBytesOutsideTheSplice(t *testing.T) {
	source := "{ \"a\" :1 ,\n\n  \"b\"  : [ 1 ,2 ]   ,\n  \"c\": {\"d\": \"é\"}  }  \n\n"
	edits := []struct {
		name string
		do   func(*Document) (*Document, error)
		want string
	}{
		{"set scalar", func(d *Document) (*Document, error) { return d.Set(Path("a"), Int(7)) },
			"{ \"a\" :7 ,\n\n  \"b\"  : [ 1 ,2 ]   ,\n  \"c\": {\"d\": \"é\"}  }  \n\n"},
		{"set nested", func(d *Document) (*Document, error) { return d.Set(Path("c", "d"), String("x")) },
			"{ \"a\" :1 ,\n\n  \"b\"  : [ 1 ,2 ]   ,\n  \"c\": {\"d\": \"x\"}  }  \n\n"},
		{"add key", func(d *Document) (*Document, error) { return d.Set(Path("e"), Null()) },
			"{ \"a\" :1 ,\n\n  \"b\"  : [ 1 ,2 ]   ,\n  \"c\": {\"d\": \"é\"},\n  \"e\" :null  }  \n\n"},
		{"append", func(d *Document) (*Document, error) { return d.Append(Int(3), Path("b")) },
			"{ \"a\" :1 ,\n\n  \"b\"  : [ 1 ,2,3 ]   ,\n  \"c\": {\"d\": \"é\"}  }  \n\n"},
		{"remove middle", func(d *Document) (*Document, error) { return d.Remove(Path("b")) },
			"{ \"a\" :1 ,\n\n  \"c\": {\"d\": \"é\"}  }  \n\n"},
		{"remove last", func(d *Document) (*Document, error) { return d.Remove(Path("c")) },
			"{ \"a\" :1 ,\n\n  \"b\"  : [ 1 ,2 ]  }  \n\n"},
	}
	for _, e := range edits {
		t.Run(e.name, func(t *testing.T) {
			next, err := e.do(mustDoc(t, source))
			if err != nil {
				t.Fatal(err)
			}
			expectText(t, next, e.want)
		})
	}
}

// Swift: OrderedJSONTests.swift "every edit result is valid JSON that Foundation reads the same way"
// (Foundation's JSONSerialization is replaced by encoding/json, used here only as an independent oracle.)
func TestEditedTextIsValid(t *testing.T) {
	current := mustDoc(t, "{\n\t\"a\": [1],\n\t\"b\": {}\n}\n")
	current = mustAppend(t, current, Int(2), Path("a"))
	current = mustSet(t, current, Path("b", "c", "d"), Array(Null(), Bool(true), String("x\ny")))
	current = mustSet(t, current, Path("e"), String("tab\there \"quoted\" \\ é"))
	current = mustRemove(t, current, Path("a", 0))
	var parsed map[string]any
	if err := json.Unmarshal(current.Bytes(), &parsed); err != nil {
		t.Fatal(err)
	}
	a, _ := parsed["a"].([]any)
	if len(a) != 1 || a[0] != float64(2) {
		t.Errorf("a = %v, want [2]", parsed["a"])
	}
	b, _ := parsed["b"].(map[string]any)
	c, _ := b["c"].(map[string]any)
	if _, ok := c["d"].([]any); !ok {
		t.Errorf("b.c.d = %v, want an array", c["d"])
	}
	if parsed["e"] != "tab\there \"quoted\" \\ é" {
		t.Errorf("e = %q", parsed["e"])
	}
	if e := mustValue(t, current, Key("e")); !e.Equal(String("tab\there \"quoted\" \\ é")) {
		t.Errorf("e = %v", e)
	}
}

// Swift: OrderedJSONTests.swift "edits on a wrong path fail without changing anything"
func TestEditErrors(t *testing.T) {
	const text = `{"a":[1],"s":"x"}`
	d := mustDoc(t, text)
	cases := []struct {
		name string
		do   func() error
		want error
	}{
		{"remove missing key", func() error { _, err := d.Remove(Path("missing")); return err }, ErrPathNotFound},
		{"remove missing index", func() error { _, err := d.Remove(Path("a", 5)); return err }, ErrPathNotFound},
		{"remove root", func() error { _, err := d.Remove(nil); return err }, ErrPathNotFound},
		{"set index past the end", func() error { _, err := d.Set(Path("a", 9), Null()); return err }, ErrPathNotFound},
		{"set below a string", func() error { _, err := d.Set(Path("s", "deeper"), Null()); return err }, ErrTypeMismatch},
		{"append to a string", func() error { _, err := d.Append(Null(), Path("s")); return err }, ErrTypeMismatch},
		{"key on an array", func() error { _, err := d.Set(Path("a", "key"), Null()); return err }, ErrTypeMismatch},
		{"number 01", func() error { _, err := d.Set(Path("n"), Number("01")); return err }, ErrInvalidValue},
		{"empty number", func() error { _, err := d.Set(Path("n"), Number("")); return err }, ErrInvalidValue},
		// Extras beyond the Swift test.
		{"index step on an object", func() error { _, err := d.Set(Path(0), Null()); return err }, ErrTypeMismatch},
		{"negative index", func() error { _, err := d.Set(Path("a", -1), Null()); return err }, ErrPathNotFound},
		{"remove below a missing key", func() error { _, err := d.Remove(Path("missing", "x")); return err }, ErrPathNotFound},
		{"index step below a missing key", func() error { _, err := d.Set(Path("missing", 0), Null()); return err }, ErrPathNotFound},
		{"bad number nested in an array", func() error { _, err := d.Set(Path("n"), Array(Number("1."))); return err }, ErrInvalidValue},
		{"remove below a scalar", func() error { _, err := d.Remove(Path("s", 0)); return err }, ErrTypeMismatch},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if err := c.do(); !errors.Is(err, c.want) {
				t.Errorf("error = %v, want %v", err, c.want)
			}
		})
	}
	if d.Text() != text {
		t.Errorf("document changed: %q", d.Text())
	}
}

// Swift: OrderedJSONTests.swift "with duplicate keys an edit targets the last one, as lookups do"
func TestDuplicateKeyEditTargetsTheLast(t *testing.T) {
	expectText(t, mustSet(t, mustDoc(t, `{"a":1,"a":2}`), Path("a"), Int(9)), `{"a":1,"a":9}`)
	expectText(t, mustRemove(t, mustDoc(t, `{"a":1,"a":2}`), Path("a")), `{"a":1}`)
}

// Extra: the edit result is reparsed, so an edit that nests past the limit fails instead of producing a
// document that cannot be read back.
func TestEditCannotExceedMaxDepth(t *testing.T) {
	deep := Null()
	for range MaxDepth {
		deep = Array(deep)
	}
	if _, err := mustDoc(t, `{}`).Set(Path("a"), deep); !errors.Is(err, ErrTooDeep) {
		t.Errorf("error = %v, want ErrTooDeep", err)
	}
}

// Extra: new text is written as JSON requires and not as encoding/json would: no HTML escapes, no sorted keys,
// control characters as lower-case \u00xx.
func TestQuoteMatchesTheSwiftWriter(t *testing.T) {
	value := Object(Member{"z", String("<a href=\"x\">&</a>\u2028\u2029\x01\x1f\x7f")}, Member{"a", Number("1E+2")})
	d := mustSet(t, mustDoc(t, `{}`), Path("k"), value)
	expectText(t, d, "{\"k\":{\"z\":\"<a href=\\\"x\\\">&</a>\u2028\u2029\\u0001\\u001f\x7f\",\"a\":1E+2}}")
}
