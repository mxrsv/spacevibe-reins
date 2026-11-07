package inventory

import (
	"os"
	"strings"
	"testing"
)

// Swift: ReadHardeningTests.swift "regular files and symlinks retain byte limits and JSON classifications"
func TestRegularReadSemantics(t *testing.T) {
	h := newTempHome(t)
	target := h.write("input.json", `{"value":true}`)
	link := h.path("link.json")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{target, link} {
		if data, ok := readData(path, 2); !ok || string(data) != `{"` {
			t.Errorf("%s: readData = %q, %v", path, data, ok)
		}
		json, status := readJSON(path)
		if status != jsonValue {
			t.Errorf("%s: regular JSON must remain readable, status %v", path, status)
			continue
		}
		if v, found := json.Member("value"); !found {
			t.Errorf("%s: no value member", path)
		} else if b, ok := v.BoolValue(); !ok || !b {
			t.Errorf("%s: value = %v", path, b)
		}
	}
	if _, status := readJSON(h.path("missing")); status != jsonMissing {
		t.Errorf("absent file status %v, want missing", status)
	}
	if _, status := readJSON(h.root); status != jsonUnreadable {
		t.Errorf("directory status %v, want unreadable", status)
	}
	invalid := h.write("invalid.json", "{")
	if _, status := readJSON(invalid); status != jsonInvalid {
		t.Errorf("malformed JSON status %v, want invalid", status)
	}
	oversized := h.write("large.json", []byte(strings.Repeat(" ", maxJSONBytes+1)))
	if _, status := readJSON(oversized); status != jsonTooLarge {
		t.Errorf("oversized file status %v, want too large", status)
	}
}
