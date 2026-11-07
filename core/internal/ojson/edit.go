package ojson

import "bytes"

type opKind uint8

const (
	opSet opKind = iota
	opRemove
	opAppend
)

type operation struct {
	kind  opKind
	value Value
}

// splice is bytes[start:end] replaced by text.
type splice struct {
	start, end  int
	replacement string
}

// Set sets the value at a path. A missing last key is added at the end of its object, and missing parent
// objects are created. Index(count) as the last step appends. An existing value is replaced in place and keeps
// its position. With duplicate keys the last one is the target.
func (d *Document) Set(path []Step, value Value) (*Document, error) {
	return d.apply(path, operation{kind: opSet, value: value})
}

// Remove removes the member or element at a path, with its separator.
func (d *Document) Remove(path []Step) (*Document, error) {
	if len(path) == 0 {
		return nil, ErrPathNotFound
	}
	return d.apply(path, operation{kind: opRemove})
}

// Append appends to the array at a path. A missing array (and missing parent objects) is created.
func (d *Document) Append(value Value, path []Step) (*Document, error) {
	return d.apply(path, operation{kind: opAppend, value: value})
}

func (d *Document) apply(path []Step, op operation) (*Document, error) {
	sp, err := d.edit(d.tree, path, op, newStyle(d))
	if err != nil {
		return nil, err
	}
	next := make([]byte, 0, len(d.bytes)-(sp.end-sp.start)+len(sp.replacement))
	next = append(next, d.bytes[:sp.start]...)
	next = append(next, sp.replacement...)
	next = append(next, d.bytes[sp.end:]...)
	return newDocument(next)
}

func (d *Document) hasNewline(start, end int) bool {
	return bytes.IndexByte(d.bytes[start:end], '\n') >= 0
}

func (d *Document) edit(n node, steps []Step, op operation, st style) (splice, error) {
	if len(steps) == 0 {
		switch op.kind {
		case opSet:
			expanded := st.multiline
			if n.kind != nodeScalar {
				expanded = st.multiline && d.hasNewline(n.start, n.end)
			}
			text, err := st.render(op.value, d.indent(n.start), expanded)
			if err != nil {
				return splice{}, err
			}
			return splice{n.start, n.end, text}, nil
		case opAppend:
			if n.kind != nodeArray {
				return splice{}, ErrTypeMismatch
			}
			existing := make([]existingItem, len(n.items))
			for i, it := range n.items {
				existing[i] = existingItem{valueEnd: it.end, start: it.start}
			}
			return d.insertion(n.start, n.end, existing, func(base string, expanded bool) (string, error) {
				return st.render(op.value, base, expanded)
			}, st)
		}
		return splice{}, ErrPathNotFound
	}
	step, rest := steps[0], steps[1:]
	switch {
	case n.kind == nodeObject && !step.isIndex:
		found := -1
		for i := len(n.members) - 1; i >= 0; i-- {
			if n.members[i].key == step.key {
				found = i
				break
			}
		}
		if found >= 0 {
			if len(rest) == 0 && op.kind == opRemove {
				starts := make([]int, len(n.members))
				ends := make([]int, len(n.members))
				for i, m := range n.members {
					starts[i], ends[i] = m.keyStart, m.value.end
				}
				return removal(len(n.members), found, n.start, n.end, starts, ends), nil
			}
			return d.edit(n.members[found].value, rest, op, st)
		}
		var leaf Value
		switch op.kind {
		case opRemove:
			return splice{}, ErrPathNotFound
		case opSet:
			leaf = op.value
		case opAppend:
			leaf = Array(op.value)
		}
		nested := leaf
		for i := len(rest) - 1; i >= 0; i-- {
			if rest[i].isIndex {
				return splice{}, ErrPathNotFound
			}
			nested = Object(Member{Key: rest[i].key, Value: nested})
		}
		existing := make([]existingItem, len(n.members))
		for i, m := range n.members {
			existing[i] = existingItem{valueEnd: m.value.end, start: m.keyStart}
		}
		return d.insertion(n.start, n.end, existing, func(base string, expanded bool) (string, error) {
			body, err := st.render(nested, base, expanded)
			if err != nil {
				return "", err
			}
			return st.quote(step.key) + st.colon + body, nil
		}, st)
	case n.kind == nodeArray && step.isIndex:
		index := step.index
		if index >= 0 && index < len(n.items) {
			if len(rest) == 0 && op.kind == opRemove {
				starts := make([]int, len(n.items))
				ends := make([]int, len(n.items))
				for i, it := range n.items {
					starts[i], ends[i] = it.start, it.end
				}
				return removal(len(n.items), index, n.start, n.end, starts, ends), nil
			}
			return d.edit(n.items[index], rest, op, st)
		}
		if index == len(n.items) && len(rest) == 0 && op.kind == opSet {
			existing := make([]existingItem, len(n.items))
			for i, it := range n.items {
				existing[i] = existingItem{valueEnd: it.end, start: it.start}
			}
			return d.insertion(n.start, n.end, existing, func(base string, expanded bool) (string, error) {
				return st.render(op.value, base, expanded)
			}, st)
		}
		return splice{}, ErrPathNotFound
	}
	return splice{}, ErrTypeMismatch
}

// existingItem is a member or element already in a container: where its value ends and where it starts
// (the key's opening quote for a member).
type existingItem struct {
	valueEnd int
	start    int
}

// insertion is where and what to write for a new member or element at the end of a container.
func (d *Document) insertion(
	containerStart, containerEnd int,
	existing []existingItem,
	text func(base string, expanded bool) (string, error),
	st style,
) (splice, error) {
	base := d.indent(containerStart)
	if len(existing) == 0 {
		expanded := st.multiline
		childBase := base + st.unit
		body, err := text(childBase, expanded)
		if err != nil {
			return splice{}, err
		}
		replacement := body
		if expanded {
			replacement = st.newline + childBase + body + st.newline + base
		}
		return splice{containerStart + 1, containerEnd - 1, replacement}, nil
	}
	last := existing[len(existing)-1]
	expanded := d.hasNewline(containerStart, containerEnd)
	childBase := base
	if expanded {
		childBase = d.indent(last.start)
	}
	body, err := text(childBase, expanded)
	if err != nil {
		return splice{}, err
	}
	replacement := st.comma() + body
	if expanded {
		replacement = "," + st.newline + childBase + body
	}
	return splice{last.valueEnd, last.valueEnd, replacement}, nil
}

// removal is the bytes to delete so that member or element index and one separator go.
func removal(count, index, containerStart, containerEnd int, starts, ends []int) splice {
	switch {
	case count == 1:
		return splice{containerStart + 1, containerEnd - 1, ""}
	case index < count-1:
		return splice{starts[index], starts[index+1], ""}
	}
	return splice{ends[index-1], ends[index], ""}
}

// indent is the leading blanks of the line holding offset.
func (d *Document) indent(offset int) string {
	lineStart := offset
	for lineStart > 0 && d.bytes[lineStart-1] != '\n' {
		lineStart--
	}
	end := lineStart
	for end < len(d.bytes) && (d.bytes[end] == ' ' || d.bytes[end] == '\t') {
		end++
	}
	return string(d.bytes[lineStart:end])
}
