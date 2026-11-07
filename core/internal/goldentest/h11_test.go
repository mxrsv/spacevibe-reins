package goldentest

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// decodeOrdered parses JSON keeping object member order and number text, which Canonical's inputs cannot.
func decodeOrdered(dec *json.Decoder) (any, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	switch tok {
	case json.Delim('['):
		items := []any{}
		for dec.More() {
			v, err := decodeOrdered(dec)
			if err != nil {
				return nil, err
			}
			items = append(items, v)
		}
		_, err := dec.Token()
		return items, err
	case json.Delim('{'):
		obj := object{}
		for dec.More() {
			key, err := dec.Token()
			if err != nil {
				return nil, err
			}
			v, err := decodeOrdered(dec)
			if err != nil {
				return nil, err
			}
			obj = append(obj, Member{key.(string), v})
		}
		_, err := dec.Token()
		return obj, err
	}
	return tok, nil
}

// collectNumbers walks a tree and records the text of every json.Number.
func collectNumbers(v any, out *[]string) {
	switch x := v.(type) {
	case json.Number:
		*out = append(*out, string(x))
	case []any:
		for _, e := range x {
			collectNumbers(e, out)
		}
	case object:
		for _, m := range x {
			collectNumbers(m.Value, out)
		}
	}
}

// H11: Go's ES6 float text equals JSON.stringify for every number in the goldens (the cost values in
// activity.json). The goldens are Node `JSON.stringify(v, null, 2)` plus a newline, so re-encoding each one in
// member order must give back the file byte for byte, and each number's own text must survive the float64 trip.
func TestFixtureH11NumbersRoundTripEveryGolden(t *testing.T) {
	fixtures, _ := FixturesDir()
	paths, err := filepath.Glob(filepath.Join(fixtures, "golden", "*.json"))
	must(t, err)
	AssertCaseCount(t, "goldens", len(paths), 6)
	sort.Strings(paths)
	total, fractional, exponent := 0, 0, 0
	for _, path := range paths {
		name := filepath.Base(path)
		data, err := os.ReadFile(path)
		must(t, err)
		dec := json.NewDecoder(strings.NewReader(string(data)))
		dec.UseNumber()
		tree, err := decodeOrdered(dec)
		must(t, err)
		if _, err := dec.Token(); err != io.EOF {
			t.Fatalf("%s: data after the first value", name)
		}

		var numbers []string
		collectNumbers(tree, &numbers)
		for _, text := range numbers {
			f, err := strconv.ParseFloat(text, 64)
			if err != nil {
				t.Errorf("%s: number %s: %v", name, text, err)
				continue
			}
			if got, _ := es6Number(f); got != text {
				t.Errorf("%s: number text %s becomes %s", name, text, got)
			}
			if strings.ContainsAny(text, ".") {
				fractional++
			}
			if strings.ContainsAny(text, "eE") {
				exponent++
			}
		}
		total += len(numbers)

		out, err := encode(tree, false)
		must(t, err)
		if string(out) != string(data) {
			t.Errorf("%s: member-order re-encoding differs from the frozen file\n%s", name, UnifiedDiff(name, "re-encoded", string(data), string(out)))
		}
		// And the sorted canonical form is stable: it parses back to the same canonical bytes.
		canon, err := Canonical(tree)
		must(t, err)
		again, err := decodeJSON(canon)
		must(t, err)
		canon2, err := Canonical(again)
		must(t, err)
		if string(canon) != string(canon2) {
			t.Errorf("%s: canonical form is not a fixed point", name)
		}
	}
	AssertCaseCount(t, "numbers across goldens", total, 1)
	t.Logf("H11: %d numbers in %d goldens (%d with a fraction, %d with an exponent): all round-trip to their own text", total, len(paths), fractional, exponent)
}
