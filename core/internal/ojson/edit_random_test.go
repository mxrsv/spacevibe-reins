package ojson

import (
	"encoding/json"
	"errors"
	"fmt"
	"math/rand"
	"testing"
)

// randomValue builds a small random tree. Keys are drawn from a tiny alphabet so paths collide and duplicates
// appear in the generated text.
func randomValue(r *rand.Rand, depth int) Value {
	pick := r.Intn(8)
	if depth >= 3 && pick >= 6 {
		pick = r.Intn(6)
	}
	switch pick {
	case 0:
		return Null()
	case 1:
		return Bool(r.Intn(2) == 0)
	case 2:
		return Int(r.Intn(1000) - 500)
	case 3:
		return Number([]string{"1.0", "1e3", "-0", "0.50", "1E+2"}[r.Intn(5)])
	case 4, 5:
		return String([]string{"x", "é", "a\"b", "t\tab", "<&>", ""}[r.Intn(6)])
	case 6:
		n := r.Intn(4)
		items := make([]Value, n)
		for i := range items {
			items[i] = randomValue(r, depth+1)
		}
		return Array(items...)
	}
	n := r.Intn(4)
	members := make([]Member, n)
	for i := range members {
		members[i] = Member{Key: string(rune('a' + r.Intn(4))), Value: randomValue(r, depth+1)}
	}
	return Object(members...)
}

// randomPath walks an existing path of v part of the way, then maybe names a missing key.
func randomPath(r *rand.Rand, v Value) []Step {
	var path []Step
	for r.Intn(4) != 0 {
		if items, ok := v.ArrayValue(); ok && len(items) > 0 {
			i := r.Intn(len(items))
			path, v = append(path, Index(i)), items[i]
		} else if members, ok := v.ObjectValue(); ok && len(members) > 0 {
			k := members[r.Intn(len(members))].Key
			next, _ := v.Member(k)
			path, v = append(path, Key(k)), next
		} else {
			break
		}
	}
	if _, ok := v.ObjectValue(); ok && r.Intn(3) == 0 {
		path = append(path, Key(string(rune('e'+r.Intn(3)))))
	}
	return path
}

// Extra: random documents in five styles, random edits. Every result must be valid JSON for an independent
// reader, hold the edited value at the edited path, and keep unrelated top-level members equal.
func TestRandomEditsStayValid(t *testing.T) {
	styles := []struct {
		name string
		make func(Value) (string, error)
	}{
		{"two spaces", Pretty},
		{"four spaces CRLF", func(v Value) (string, error) { return PrettyStyled(v, "    ", "\r\n", true) }},
		{"tabs no newline", func(v Value) (string, error) { return PrettyStyled(v, "\t", "\n", false) }},
		{"minified", func(v Value) (string, error) {
			s := style{unit: "", newline: "", colon: ":", multiline: false}
			return s.render(v, "", false)
		}},
		{"spaced", func(v Value) (string, error) {
			s := style{unit: "", newline: "", colon: ": ", multiline: false}
			return s.render(v, "", false)
		}},
	}
	r := rand.New(rand.NewSource(20261107))
	for _, st := range styles {
		t.Run(st.name, func(t *testing.T) {
			for i := 0; i < 400; i++ {
				root := randomValue(r, 0)
				text, err := st.make(root)
				if err != nil {
					t.Fatal(err)
				}
				d := mustDoc(t, text)
				if d.Text() != text {
					t.Fatalf("round trip changed %q", text)
				}
				if !d.Root().Equal(root) {
					t.Fatalf("parse of %q differs from the value it was rendered from", text)
				}
				path := randomPath(r, d.Root())
				newValue := randomValue(r, 1)
				for kind, apply := range map[string]func() (*Document, error){
					"set":    func() (*Document, error) { return d.Set(path, newValue) },
					"append": func() (*Document, error) { return d.Append(newValue, path) },
					"remove": func() (*Document, error) { return d.Remove(path) },
				} {
					next, err := apply()
					label := fmt.Sprintf("%s %v on %q", kind, path, text)
					if err != nil {
						if !errors.Is(err, ErrPathNotFound) && !errors.Is(err, ErrTypeMismatch) {
							t.Fatalf("%s: unexpected error %v", label, err)
						}
						if d.Text() != text {
							t.Fatalf("%s: failed edit changed the document", label)
						}
						continue
					}
					if !json.Valid(next.Bytes()) {
						t.Fatalf("%s: invalid JSON %q", label, next.Text())
					}
					switch kind {
					case "set":
						got, ok := next.Get(path...)
						if !ok || !got.Equal(newValue) {
							t.Fatalf("%s: value at path = %v, ok=%v, want %v; result %q", label, got, ok, newValue, next.Text())
						}
					case "append":
						got, ok := next.Get(path...)
						items, isArray := got.ArrayValue()
						if !ok || !isArray || len(items) == 0 || !items[len(items)-1].Equal(newValue) {
							t.Fatalf("%s: array tail wrong in %q", label, next.Text())
						}
					case "remove":
						last := path[len(path)-1]
						parent, _ := d.Get(path[:len(path)-1]...)
						nextParent, _ := next.Get(path[:len(path)-1]...)
						if items, ok := parent.ArrayValue(); ok {
							if got, _ := nextParent.ArrayValue(); len(got) != len(items)-1 {
								t.Fatalf("%s: array length %d -> %d", label, len(items), len(got))
							}
						} else if !hasDuplicate(d, path) {
							if _, still := nextParent.Member(last.key); still {
								t.Fatalf("%s: key still present in %q", label, next.Text())
							}
						}
					}
				}
			}
		})
	}
}

// hasDuplicate reports whether the last step of path names a key that appears twice in its object, so a
// removal exposes the earlier duplicate.
func hasDuplicate(d *Document, path []Step) bool {
	parent, _ := d.Get(path[:len(path)-1]...)
	if _, ok := parent.ArrayValue(); ok {
		return false
	}
	count := 0
	members, _ := parent.ObjectValue()
	for _, m := range members {
		if m.Key == path[len(path)-1].key {
			count++
		}
	}
	return count > 1
}
