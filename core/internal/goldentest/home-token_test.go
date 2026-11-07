package goldentest

import (
	"bytes"
	"encoding/json"
	"reflect"
	"testing"
)

// Go addition: a json.Number is a string kind in reflect, and HomeToken once turned it into a plain
// string, so "count": 8 became "8" and a number-vs-string mismatch passed. Numbers and every other
// non-string leaf must come back with the same type.
func TestHomeTokenKeepsNumbersAndOtherLeaves(t *testing.T) {
	tree := map[string]any{
		"count":  json.Number("8"),
		"ratio":  json.Number("0.25"),
		"big":    json.Number("12345678901234567890"),
		"int":    7,
		"float":  1.5,
		"flag":   true,
		"none":   nil,
		"text":   "8",
		"list":   []any{json.Number("1"), json.Number("2.50"), "x", false, nil},
		"nested": map[string]any{"n": json.Number("-3"), "path": CanonicalRoot + "/a"},
		"typed":  map[string][]json.Number{CanonicalRoot + "/k": {json.Number("4")}},
		"slice":  []json.Number{json.Number("5")},
	}
	got := HomeToken(tree, CanonicalRoot).(map[string]any)

	// Same tree except the path text and the typed containers, which come back as []any / map[string]any.
	want := map[string]any{
		"count": json.Number("8"), "ratio": json.Number("0.25"), "big": json.Number("12345678901234567890"),
		"int": 7, "float": 1.5, "flag": true, "none": nil, "text": "8",
		"list":   []any{json.Number("1"), json.Number("2.50"), "x", false, nil},
		"nested": map[string]any{"n": json.Number("-3"), "path": "$HOME/a"},
		"typed":  map[string]any{"$HOME/k": []any{json.Number("4")}},
		"slice":  []any{json.Number("5")},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("HomeToken changed a leaf type or value:\n got %#v\nwant %#v", got, want)
	}
	if _, ok := got["count"].(json.Number); !ok {
		t.Errorf("count is %T, want json.Number", got["count"])
	}
	if _, ok := got["text"].(string); !ok {
		t.Errorf("text is %T, want string", got["text"])
	}

	// With no root in the tree the canonical bytes do not move, and a number still differs from a string.
	plain := map[string]any{"count": json.Number("8"), "list": []any{json.Number("1")}}
	before, err := Canonical(plain)
	if err != nil {
		t.Fatal(err)
	}
	after, err := Canonical(HomeToken(plain, CanonicalRoot))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Errorf("canonical bytes changed:\n%s\n%s", before, after)
	}
	asString, _ := Canonical(HomeToken(map[string]any{"count": "8", "list": []any{"1"}}, CanonicalRoot))
	if bytes.Equal(before, asString) {
		t.Error("a number and the same digits as a string produced equal canonical bytes")
	}
}
