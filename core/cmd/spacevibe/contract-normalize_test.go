package main

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"sort"
	"strings"
)

// normalizer makes a recorded conversation the same on every run: a home folder becomes $HOME, a journal id
// or any other masked text becomes its placeholder, and the values that follow the clock become "$CLOCK".
// A line is parsed and written back with sorted keys, so a transcript that opts in is not in wire order.
type normalizer struct {
	masks [][2]string
}

// newNormalizer masks each home, and the spelling of it with links resolved (macOS /var is a link).
func newNormalizer(homes ...string) *normalizer {
	n := &normalizer{}
	for _, h := range homes {
		n.mask(h, "$HOME")
		if r, err := filepath.EvalSymlinks(h); err == nil && r != h {
			n.mask(r, "$HOME")
		}
	}
	return n
}

// mask replaces old with replacement in every string of every later-rendered line. Longest first.
func (n *normalizer) mask(old, replacement string) {
	if old == "" {
		return
	}
	n.masks = append(n.masks, [2]string{old, replacement})
	sort.SliceStable(n.masks, func(i, j int) bool { return len(n.masks[i][0]) > len(n.masks[j][0]) })
}

func (n *normalizer) text(s string) string {
	for _, m := range n.masks {
		s = strings.ReplaceAll(s, m[0], m[1])
	}
	return s
}

// clockKeys are members whose value moves with the wall clock.
var clockKeys = map[string]bool{"current": true, "ageMs": true, "lastWriteAgoMs": true}

// line renders one wire line; a line that is not JSON gets only the text masks.
func (n *normalizer) line(l string) string {
	dec := json.NewDecoder(strings.NewReader(l))
	dec.UseNumber()
	var v any
	if dec.Decode(&v) != nil {
		return n.text(l)
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if enc.Encode(n.walk("", v)) != nil {
		return n.text(l)
	}
	return strings.TrimSuffix(buf.String(), "\n")
}

func (n *normalizer) walk(key string, v any) any {
	switch t := v.(type) {
	case map[string]any:
		out := make(map[string]any, len(t))
		for k, child := range t {
			out[n.text(k)] = n.walk(k, child)
		}
		return out
	case []any:
		out := make([]any, len(t))
		for i, child := range t {
			out[i] = n.walk(key, child)
		}
		return out
	case string:
		if key == "at" && strings.HasSuffix(t, "Z") {
			return "$TIME"
		}
		return n.text(t)
	case bool, json.Number:
		if clockKeys[key] {
			return "$CLOCK"
		}
	}
	return v
}
