package goldentest

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"reflect"
	"slices"
	"strconv"
	"unicode/utf8"
)

// errUnsupported is fixed text: it never quotes the value (S-R3).
var errUnsupported = errors.New("goldentest: the value has a type that is not JSON")

// Member is one key and value of an ordered object. Canonical sorts the members of every object, so order
// only matters to code that needs it kept (the ordered golden decoder in tests).
type Member struct {
	Key   string
	Value any
}

// object is an object that keeps its member order; Canonical never receives one from callers.
type object []Member

// Canonical is the one writer both sides of a golden comparison go through: object keys sorted in UTF-16 code
// unit order (as Array.prototype.sort), numbers as JavaScript prints them (H11), 2-space indent with ": "
// after a key, "[]" and "{}" for empty containers, no HTML escaping, U+2028 and U+2029 written raw as
// JSON.stringify does, and one trailing newline, so a frozen golden written by Node reads back byte for byte.
//
// v is a JSON tree: nil, bool, string, any Go integer or float, json.Number, []any, map[string]any, and any
// slice, array or string-keyed map of those. Structs are refused. Invalid UTF-8 is written as U+FFFD, which is
// what a JavaScript string decoded from the same bytes holds.
func Canonical(v any) ([]byte, error) { return encode(v, true) }

// CanonicalSHA256 is the hex SHA-256 of Canonical(v); tests log it on success.
func CanonicalSHA256(v any) (string, error) {
	out, err := Canonical(v)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(out)
	return hex.EncodeToString(sum[:]), nil
}

func encode(v any, sortKeys bool) ([]byte, error) {
	var buf bytes.Buffer
	if err := writeValue(&buf, v, 0, sortKeys); err != nil {
		return nil, err
	}
	buf.WriteByte('\n')
	return buf.Bytes(), nil
}

func writeValue(buf *bytes.Buffer, v any, depth int, sortKeys bool) error {
	switch x := v.(type) {
	case nil:
		buf.WriteString("null")
	case bool:
		buf.WriteString(strconv.FormatBool(x))
	case string:
		writeString(buf, x)
	case json.Number:
		f, err := strconv.ParseFloat(string(x), 64)
		if err != nil {
			return errors.New("goldentest: a number is not a finite JSON number")
		}
		return writeFloat(buf, f)
	case float64:
		return writeFloat(buf, x)
	case float32:
		return writeFloat(buf, float64(x))
	case int:
		buf.WriteString(strconv.FormatInt(int64(x), 10))
	case int64:
		buf.WriteString(strconv.FormatInt(x, 10))
	case []any:
		return writeArray(buf, len(x), func(i int) any { return x[i] }, depth, sortKeys)
	case map[string]any:
		members := make([]Member, 0, len(x))
		for k, val := range x {
			members = append(members, Member{k, val})
		}
		return writeObject(buf, members, depth, sortKeys)
	case object:
		return writeObject(buf, x, depth, sortKeys)
	default:
		return writeReflected(buf, reflect.ValueOf(v), depth, sortKeys)
	}
	return nil
}

func writeReflected(buf *bytes.Buffer, rv reflect.Value, depth int, sortKeys bool) error {
	switch rv.Kind() {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		buf.WriteString(strconv.FormatInt(rv.Int(), 10))
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		buf.WriteString(strconv.FormatUint(rv.Uint(), 10))
	case reflect.Float32, reflect.Float64:
		return writeFloat(buf, rv.Float())
	case reflect.Bool:
		buf.WriteString(strconv.FormatBool(rv.Bool()))
	case reflect.String:
		writeString(buf, rv.String())
	case reflect.Slice, reflect.Array:
		return writeArray(buf, rv.Len(), func(i int) any { return rv.Index(i).Interface() }, depth, sortKeys)
	case reflect.Map:
		if rv.Type().Key().Kind() != reflect.String {
			return errUnsupported
		}
		members := make([]Member, 0, rv.Len())
		for it := rv.MapRange(); it.Next(); {
			members = append(members, Member{it.Key().String(), it.Value().Interface()})
		}
		return writeObject(buf, members, depth, sortKeys)
	default:
		return errUnsupported
	}
	return nil
}

func writeFloat(buf *bytes.Buffer, f float64) error {
	text, err := es6Number(f)
	if err != nil {
		return err
	}
	buf.WriteString(text)
	return nil
}

func indent(buf *bytes.Buffer, depth int) {
	buf.WriteByte('\n')
	for range depth {
		buf.WriteString("  ")
	}
}

func writeArray(buf *bytes.Buffer, n int, at func(int) any, depth int, sortKeys bool) error {
	if n == 0 {
		buf.WriteString("[]")
		return nil
	}
	buf.WriteByte('[')
	for i := range n {
		if i > 0 {
			buf.WriteByte(',')
		}
		indent(buf, depth+1)
		if err := writeValue(buf, at(i), depth+1, sortKeys); err != nil {
			return err
		}
	}
	indent(buf, depth)
	buf.WriteByte(']')
	return nil
}

func writeObject(buf *bytes.Buffer, members []Member, depth int, sortKeys bool) error {
	if len(members) == 0 {
		buf.WriteString("{}")
		return nil
	}
	if sortKeys {
		members = slices.Clone(members)
		slices.SortStableFunc(members, func(a, b Member) int { return compareUTF16(a.Key, b.Key) })
	}
	buf.WriteByte('{')
	for i, m := range members {
		if i > 0 {
			buf.WriteByte(',')
		}
		indent(buf, depth+1)
		writeString(buf, m.Key)
		buf.WriteString(": ")
		if err := writeValue(buf, m.Value, depth+1, sortKeys); err != nil {
			return err
		}
	}
	indent(buf, depth)
	buf.WriteByte('}')
	return nil
}

// writeString is JSON.stringify's QuoteJSONString: escape the quote, the backslash and C0 controls only.
func writeString(buf *bytes.Buffer, s string) {
	const hexDigits = "0123456789abcdef"
	buf.WriteByte('"')
	for _, r := range s { // invalid bytes arrive as U+FFFD, one per bad byte
		switch {
		case r == '"':
			buf.WriteString(`\"`)
		case r == '\\':
			buf.WriteString(`\\`)
		case r == '\b':
			buf.WriteString(`\b`)
		case r == '\f':
			buf.WriteString(`\f`)
		case r == '\n':
			buf.WriteString(`\n`)
		case r == '\r':
			buf.WriteString(`\r`)
		case r == '\t':
			buf.WriteString(`\t`)
		case r < 0x20:
			buf.WriteString(`\u00`)
			buf.WriteByte(hexDigits[r>>4])
			buf.WriteByte(hexDigits[r&0xf])
		default:
			buf.WriteRune(r)
		}
	}
	buf.WriteByte('"')
}

// compareUTF16 orders strings by UTF-16 code units, the order Array.prototype.sort uses.
func compareUTF16(a, b string) int {
	for a != "" && b != "" {
		ra, sa := utf8.DecodeRuneInString(a)
		rb, sb := utf8.DecodeRuneInString(b)
		if ra != rb {
			if ua, ub := firstUnit(ra), firstUnit(rb); ua != ub {
				return int(ua) - int(ub)
			}
			return int(ra) - int(rb) // same high surrogate: compare the low halves
		}
		a, b = a[sa:], b[sb:]
	}
	return len(a) - len(b)
}

// firstUnit is the first UTF-16 code unit of r.
func firstUnit(r rune) rune {
	if r >= 0x10000 {
		return 0xD7C0 + r>>10
	}
	return r
}

// decodeJSON parses JSON bytes into a generic tree whose numbers keep their text (json.Number). Errors
// are fixed text, never the input.
func decodeJSON(data []byte) (any, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return nil, errors.New("goldentest: the file is not valid JSON")
	}
	if dec.More() {
		return nil, errors.New("goldentest: the file has data after the first JSON value")
	}
	return v, nil
}
