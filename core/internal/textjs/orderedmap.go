package textjs

// Entry is one key and value of an OrderedMap.
type Entry[V any] struct {
	Key   string
	Value V
}

// OrderedMap is a string-keyed map that remembers insertion order, like a JavaScript
// Map: setting an existing key keeps its first position. The zero value is ready to use.
type OrderedMap[V any] struct {
	keys    []string
	storage map[string]V
}

// Len is the number of keys.
func (m *OrderedMap[V]) Len() int { return len(m.keys) }

// IsEmpty reports whether the map has no keys.
func (m *OrderedMap[V]) IsEmpty() bool { return len(m.keys) == 0 }

// Keys returns a copy of the keys in insertion order.
func (m *OrderedMap[V]) Keys() []string { return append([]string(nil), m.keys...) }

// Values returns the values in insertion order.
func (m *OrderedMap[V]) Values() []V {
	out := make([]V, 0, len(m.keys))
	for _, k := range m.keys {
		out = append(out, m.storage[k])
	}
	return out
}

// Entries returns the key and value pairs in insertion order.
func (m *OrderedMap[V]) Entries() []Entry[V] {
	out := make([]Entry[V], 0, len(m.keys))
	for _, k := range m.keys {
		out = append(out, Entry[V]{k, m.storage[k]})
	}
	return out
}

// Last returns the value of the most recently inserted key.
func (m *OrderedMap[V]) Last() (V, bool) {
	if len(m.keys) == 0 {
		var zero V
		return zero, false
	}
	return m.storage[m.keys[len(m.keys)-1]], true
}

// Get returns the value for key.
func (m *OrderedMap[V]) Get(key string) (V, bool) {
	v, ok := m.storage[key]
	return v, ok
}

// Set stores value under key. A new key goes last; an existing key keeps its position.
func (m *OrderedMap[V]) Set(key string, value V) {
	if m.storage == nil {
		m.storage = map[string]V{}
	}
	if _, ok := m.storage[key]; !ok {
		m.keys = append(m.keys, key)
	}
	m.storage[key] = value
}

// Delete removes key; the other keys keep their order. A missing key is a no-op.
func (m *OrderedMap[V]) Delete(key string) {
	if _, ok := m.storage[key]; !ok {
		return
	}
	delete(m.storage, key)
	for i, k := range m.keys {
		if k == key {
			m.keys = append(m.keys[:i], m.keys[i+1:]...)
			return
		}
	}
}

// RemoveAll empties the map.
func (m *OrderedMap[V]) RemoveAll() {
	m.keys = nil
	m.storage = nil
}
