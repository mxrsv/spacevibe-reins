// Package ojson reads and edits JSON config files without disturbing the bytes an edit does not touch.
//
// It ports three Swift files as one package, because they are one dependency cycle there:
// Sources/ReinsCore/JSONValue.swift (the value model), JSONParser.swift (the byte-position parser) and
// OrderedJSON.swift (the document and its splice edits).
//
// encoding/json must not be used for config files: it sorts object keys, escapes <, > and & (and U+2028/2029),
// rewrites numbers through float64, and its errors quote input text. This package keeps the exact bytes of
// a document, parses a tree that records the byte range of every value, and an edit splices new text into only
// the region it changes. Numbers keep their source text. Duplicate keys are kept, and lookups and edits use the
// last one, as JSON.parse does. Nesting deeper than MaxDepth is rejected.
package ojson

import "strconv"

// Kind tells which JSON type a Value holds.
type Kind uint8

// The JSON types. The zero Value is KindNull.
const (
	KindNull Kind = iota
	KindBool
	KindNumber
	KindString
	KindArray
	KindObject
)

// Member is one "key": value pair. Objects keep their members in file order, duplicates included.
type Member struct {
	Key   string
	Value Value
}

// Value is a JSON value that keeps object key order. A number keeps its source text, so 1.0 and 1e3 survive
// a round trip. The zero Value is null. Values are not changed by this package after they are built.
type Value struct {
	kind    Kind
	b       bool
	s       string // number text or string content
	items   []Value
	members []Member
}

// Null is the JSON null.
func Null() Value { return Value{} }

// Bool is a JSON true or false.
func Bool(b bool) Value { return Value{kind: KindBool, b: b} }

// Number is a JSON number written as the given text. Writing it checks the JSON number grammar.
func Number(text string) Value { return Value{kind: KindNumber, s: text} }

// Int is a JSON number for an integer.
func Int(n int) Value { return Number(strconv.Itoa(n)) }

// String is a JSON string.
func String(s string) Value { return Value{kind: KindString, s: s} }

// Array is a JSON array.
func Array(items ...Value) Value { return Value{kind: KindArray, items: items} }

// Object is a JSON object with the members in the given order.
func Object(members ...Member) Value { return Value{kind: KindObject, members: members} }

// Kind reports the JSON type.
func (v Value) Kind() Kind { return v.kind }

// StringValue returns the string content when v is a string.
func (v Value) StringValue() (string, bool) { return v.s, v.kind == KindString }

// BoolValue returns the boolean when v is a bool.
func (v Value) BoolValue() (bool, bool) { return v.b, v.kind == KindBool }

// NumberText returns the source text of a number.
func (v Value) NumberText() (string, bool) { return v.s, v.kind == KindNumber }

// ArrayValue returns the elements when v is an array. The slice must not be modified.
func (v Value) ArrayValue() ([]Value, bool) { return v.items, v.kind == KindArray }

// ObjectValue returns the members when v is an object. The slice must not be modified.
func (v Value) ObjectValue() ([]Member, bool) { return v.members, v.kind == KindObject }

// Member returns the value for a key. With duplicate keys the last one wins, as in JSON.parse.
// Keys are compared byte for byte.
func (v Value) Member(key string) (Value, bool) {
	if v.kind != KindObject {
		return Value{}, false
	}
	for i := len(v.members) - 1; i >= 0; i-- {
		if v.members[i].Key == key {
			return v.members[i].Value, true
		}
	}
	return Value{}, false
}

// Element returns the array element at index.
func (v Value) Element(index int) (Value, bool) {
	if v.kind != KindArray || index < 0 || index >= len(v.items) {
		return Value{}, false
	}
	return v.items[index], true
}

// Equal reports whether two values have the same type and content. Object member order matters, and numbers
// compare by their text.
func (v Value) Equal(o Value) bool {
	if v.kind != o.kind {
		return false
	}
	switch v.kind {
	case KindBool:
		return v.b == o.b
	case KindNumber, KindString:
		return v.s == o.s
	case KindArray:
		if len(v.items) != len(o.items) {
			return false
		}
		for i := range v.items {
			if !v.items[i].Equal(o.items[i]) {
				return false
			}
		}
	case KindObject:
		if len(v.members) != len(o.members) {
			return false
		}
		for i := range v.members {
			if v.members[i].Key != o.members[i].Key || !v.members[i].Value.Equal(o.members[i].Value) {
				return false
			}
		}
	}
	return true
}

// Step is one step of a key path: an object key or an array index.
// {Key("permissions"), Key("allow"), Index(0)} is a path.
type Step struct {
	key     string
	index   int
	isIndex bool
}

// Key is a path step into an object member.
func Key(key string) Step { return Step{key: key} }

// Index is a path step into an array element.
func Index(index int) Step { return Step{index: index, isIndex: true} }

// Path builds a path from alternating keys: strings become Key steps and ints become Index steps.
// It panics on any other type, so it is for literals in code, not for input.
func Path(steps ...any) []Step {
	out := make([]Step, len(steps))
	for i, s := range steps {
		switch s := s.(type) {
		case string:
			out[i] = Key(s)
		case int:
			out[i] = Index(s)
		default:
			panic("ojson.Path: step must be a string or an int")
		}
	}
	return out
}
