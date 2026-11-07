// Package toml is a forgiving, read-only TOML reader for Codex config.toml and agent .toml files.
// It ports Sources/ReinsCore/TOMLReader.swift by hand: Read never fails, lines it cannot read are
// skipped and counted in Document.SkippedLines, bare tokens it cannot classify are kept as KindRaw,
// and the last assignment of a key wins. It does not validate TOML, so a file Codex rejects can
// still be shown. A strict parser (go-toml) is not used because it would reject such files and
// its errors quote file text.
package toml

import (
	"errors"
	"os"
	"slices"
	"unicode/utf8"
)

// Kind tells which field of a Value is meaningful.
type Kind uint8

const (
	KindString  Kind = iota // Str
	KindInteger             // Int
	KindFloat               // Float
	KindBool                // Bool
	KindArray               // Items
	KindTable               // Pairs: an inline table { a = 1 }, pairs in file order
	// KindRaw is a bare token that is none of the above (a date and time, inf, a malformed
	// number), kept as written in Str.
	KindRaw
)

// Value is a TOML value.
type Value struct {
	Kind  Kind
	Str   string
	Int   int64
	Float float64
	Bool  bool
	Items []Value
	Pairs []Pair
}

// Pair is one key of an inline table. Dotted keys are joined with ".".
type Pair struct {
	Key   string
	Value Value
}

// AsString returns the string when v is a KindString.
func (v Value) AsString() (string, bool) { return v.Str, v.Kind == KindString }

// AsBool returns the bool when v is a KindBool.
func (v Value) AsBool() (bool, bool) { return v.Bool, v.Kind == KindBool }

// AsInt returns the integer when v is a KindInteger.
func (v Value) AsInt() (int64, bool) { return v.Int, v.Kind == KindInteger }

// AsArray returns the elements when v is a KindArray.
func (v Value) AsArray() ([]Value, bool) { return v.Items, v.Kind == KindArray }

// AsTable returns the pairs when v is a KindTable.
func (v Value) AsTable() ([]Pair, bool) { return v.Pairs, v.Kind == KindTable }

// Strings returns the string elements of an array; other elements are skipped. Never nil.
func (v Value) Strings() []string {
	out := []string{}
	if v.Kind != KindArray {
		return out
	}
	for _, item := range v.Items {
		if item.Kind == KindString {
			out = append(out, item.Str)
		}
	}
	return out
}

// Get returns a key of an inline table; the last pair with that key wins.
func (v Value) Get(key string) (Value, bool) {
	if v.Kind != KindTable {
		return Value{}, false
	}
	for i := len(v.Pairs) - 1; i >= 0; i-- {
		if v.Pairs[i].Key == key {
			return v.Pairs[i].Value, true
		}
	}
	return Value{}, false
}

// Entry is one key = value line (or a multi-line value) and the table it sits in.
type Entry struct {
	// Table is the header path in effect: [projects."/a/b"] is {"projects", "/a/b"}; empty at top level.
	Table []string
	// KeyPath is the key as written, split at dots outside quotes. a.b = 1 is {"a", "b"}.
	KeyPath []string
	// Value is nil when the value could not be read; the key still counts as present.
	Value *Value
	// Line is the 1-based line where the key starts.
	Line int
	// InArrayTable is true for entries under [[name]].
	InArrayTable bool
}

// Key is KeyPath joined with ".".
func (e Entry) Key() string { return join(e.KeyPath) }

// TableHeader is a [path] or [[path]] line.
type TableHeader struct {
	Path []string
	// IsArray is true for [[name]] rather than [name].
	IsArray bool
}

// Document is the result of reading one file.
type Document struct {
	Entries []Entry
	Tables  []TableHeader
	// SkippedLines counts lines the reader could not make sense of and skipped.
	SkippedLines int
}

// EntriesIn returns the entries whose table equals table, in file order.
func (d Document) EntriesIn(table []string) []Entry {
	out := []Entry{}
	for _, e := range d.Entries {
		if slices.Equal(e.Table, table) {
			out = append(out, e)
		}
	}
	return out
}

// Value returns the value of key in table. The last assignment wins, even when its value is
// unreadable (then ok is false).
func (d Document) Value(table []string, key string) (Value, bool) {
	for i := len(d.Entries) - 1; i >= 0; i-- {
		e := d.Entries[i]
		if slices.Equal(e.Table, table) && e.Key() == key {
			if e.Value == nil {
				return Value{}, false
			}
			return *e.Value, true
		}
	}
	return Value{}, false
}

// TablePaths returns header paths that start with prefix, in file order, without repeats.
func (d Document) TablePaths(prefix []string) [][]string {
	seen := [][]string{}
	for _, h := range d.Tables {
		if len(h.Path) >= len(prefix) && slices.Equal(h.Path[:len(prefix)], prefix) &&
			!slices.ContainsFunc(seen, func(p []string) bool { return slices.Equal(p, h.Path) }) {
			seen = append(seen, h.Path)
		}
	}
	return seen
}

// ErrUnreadable is returned by ReadFile when the file is missing, unreadable or not UTF-8.
var ErrUnreadable = errors.New("TOML file is missing or is not UTF-8 text")

// Read parses text. It never fails.
func Read(text string) Document {
	p := parser{b: []byte(text)}
	p.indexLines()
	return p.run()
}

// ReadFile reads the document at path. A leading UTF-8 byte order mark is dropped, as
// Foundation's String(data:encoding:) does. The error is fixed text and never quotes the file.
func ReadFile(path string) (Document, error) {
	data, err := os.ReadFile(path)
	if err != nil || !utf8.Valid(data) {
		return Document{}, ErrUnreadable
	}
	if len(data) >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
		data = data[3:]
	}
	return Read(string(data)), nil
}
