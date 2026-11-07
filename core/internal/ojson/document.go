package ojson

import "unicode/utf8"

// Document is a JSON document that is edited in place. It keeps the file's exact bytes and a parsed tree with
// byte positions; an edit splices new text into only the region it changes and parses the result again. So:
//   - a file that is read and written back unchanged is the same bytes (indent, CRLF, key order, trailing
//     newline, spacing);
//   - after an edit, every byte outside the edited member, element or separator is untouched;
//   - new text copies the document's style: tab or N spaces, CRLF or LF, spacing after ":" and ",".
//
// A Document is immutable: every edit returns a new one. Only strict JSON is accepted (no comments, no trailing
// commas, no BOM), the same files JSON.parse accepts.
type Document struct {
	bytes []byte
	root  Value
	tree  node
}

// Parse reads a document from UTF-8 bytes. The result does not share memory with data.
func Parse(data []byte) (*Document, error) {
	return newDocument(append([]byte(nil), data...))
}

// ParseString reads a document from text.
func ParseString(text string) (*Document, error) {
	return newDocument([]byte(text))
}

// newDocument takes ownership of bytes.
func newDocument(bytes []byte) (*Document, error) {
	if !utf8.Valid(bytes) {
		return nil, ErrInvalidUTF8
	}
	tree, err := parseDocument(bytes)
	if err != nil {
		return nil, err
	}
	return &Document{bytes: bytes, root: tree.value(), tree: tree}, nil
}

// Bytes returns a copy of the exact bytes of the document.
func (d *Document) Bytes() []byte { return append([]byte(nil), d.bytes...) }

// Text is the document as a string.
func (d *Document) Text() string { return string(d.bytes) }

// Root is the parsed root value.
func (d *Document) Root() Value { return d.root }

// Get returns the value at a key path, or false when the path does not exist.
func (d *Document) Get(path ...Step) (Value, bool) {
	current := d.root
	for _, step := range path {
		var ok bool
		if step.isIndex {
			current, ok = current.Element(step.index)
		} else {
			current, ok = current.Member(step.key)
		}
		if !ok {
			return Value{}, false
		}
	}
	return current, true
}
