package textjs

import (
	"slices"
	"testing"
)

// The Swift tests only use OrderedMap through the fold and Activity tests (no direct vector),
// so these cases pin the documented behavior: JavaScript Map insertion order.
func TestOrderedMap(t *testing.T) {
	var m OrderedMap[int]
	if !m.IsEmpty() || m.Len() != 0 {
		t.Fatal("zero value must be empty")
	}
	if _, ok := m.Last(); ok {
		t.Error("Last on empty must report false")
	}
	if _, ok := m.Get("x"); ok {
		t.Error("Get on empty must report false")
	}
	m.Set("b", 1)
	m.Set("a", 2)
	m.Set("c", 3)
	m.Set("b", 10) // a repeated Set keeps the first position
	if got := m.Keys(); !slices.Equal(got, []string{"b", "a", "c"}) {
		t.Errorf("Keys = %q", got)
	}
	if got := m.Values(); !slices.Equal(got, []int{10, 2, 3}) {
		t.Errorf("Values = %v", got)
	}
	if got := m.Entries(); !slices.Equal(got, []Entry[int]{{"b", 10}, {"a", 2}, {"c", 3}}) {
		t.Errorf("Entries = %v", got)
	}
	if v, ok := m.Last(); !ok || v != 3 {
		t.Errorf("Last = %d, %v", v, ok)
	}
	if v, ok := m.Get("a"); !ok || v != 2 {
		t.Errorf("Get(a) = %d, %v", v, ok)
	}
	// Keys returns a copy.
	keys := m.Keys()
	keys[0] = "zzz"
	if m.Keys()[0] != "b" {
		t.Error("Keys must return a copy")
	}

	m.Delete("a")
	m.Delete("missing")
	if got := m.Keys(); !slices.Equal(got, []string{"b", "c"}) || m.Len() != 2 {
		t.Errorf("after Delete: %q", got)
	}
	if _, ok := m.Get("a"); ok {
		t.Error("deleted key must be gone")
	}
	// A deleted key set again goes last, like Map.delete then Map.set.
	m.Set("a", 7)
	if got := m.Keys(); !slices.Equal(got, []string{"b", "c", "a"}) {
		t.Errorf("after re-Set: %q", got)
	}
	// A zero value is a real value, not a deletion (Swift deletes only on nil).
	m.Set("z", 0)
	if v, ok := m.Get("z"); !ok || v != 0 || m.Len() != 4 {
		t.Errorf("zero value: %d %v len=%d", v, ok, m.Len())
	}

	m.RemoveAll()
	if !m.IsEmpty() || len(m.Values()) != 0 || len(m.Entries()) != 0 {
		t.Error("RemoveAll must empty the map")
	}
	m.Set("again", 1)
	if got := m.Keys(); !slices.Equal(got, []string{"again"}) {
		t.Errorf("after RemoveAll: %q", got)
	}
}

func TestOrderedMapKeysAreBytes(t *testing.T) {
	// Swift Dictionary keys use canonical equivalence (plan H14); Go keys are bytes,
	// so NFC and NFD forms of one name are two keys here.
	var m OrderedMap[int]
	m.Set("é", 1)
	m.Set("é", 2)
	if m.Len() != 2 {
		t.Errorf("Len = %d, want 2 (byte keys)", m.Len())
	}
}
