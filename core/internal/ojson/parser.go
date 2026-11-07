package ojson

import (
	"strings"
	"unicode/utf8"
)

// MaxDepth is the deepest nesting of arrays and objects the parser accepts.
const MaxDepth = 256

type nodeKind uint8

const (
	nodeScalar nodeKind = iota
	nodeArray
	nodeObject
)

// node is parsed JSON with the byte range [start, end) of every value in the source.
type node struct {
	kind    nodeKind
	start   int
	end     int
	scalar  Value
	items   []node
	members []nodeMember
}

type nodeMember struct {
	key      string
	keyStart int
	keyEnd   int
	value    node
}

func (n node) value() Value {
	switch n.kind {
	case nodeArray:
		items := make([]Value, len(n.items))
		for i, it := range n.items {
			items[i] = it.value()
		}
		return Value{kind: KindArray, items: items}
	case nodeObject:
		members := make([]Member, len(n.members))
		for i, m := range n.members {
			members[i] = Member{Key: m.key, Value: m.value.value()}
		}
		return Value{kind: KindObject, members: members}
	}
	return n.scalar
}

// firstMemberSeparator is the text between the first key's closing quote and its value (": "), when the
// document has an object member. An empty object ends the search in that branch.
func (n node) firstMemberSeparator(bytes []byte) (string, bool) {
	switch n.kind {
	case nodeObject:
		if len(n.members) > 0 {
			first := n.members[0]
			return string(bytes[first.keyEnd:first.value.start]), true
		}
	case nodeArray:
		for _, it := range n.items {
			if sep, ok := it.firstMemberSeparator(bytes); ok {
				return sep, true
			}
		}
	}
	return "", false
}

// parser is a strict JSON parser (RFC 8259) over UTF-8 bytes that already passed UTF-8 validation.
type parser struct {
	bytes []byte
	index int
	depth int
}

func parseDocument(bytes []byte) (node, error) {
	p := &parser{bytes: bytes}
	p.skipBlanks()
	n, err := p.parseValue()
	if err != nil {
		return node{}, err
	}
	p.skipBlanks()
	if p.index != len(p.bytes) {
		return node{}, p.fail(TrailingContent)
	}
	return n, nil
}

// fail reports a problem at the current index, as a 1-based line and byte column.
func (p *parser) fail(problem Problem) error {
	line, column := 1, 1
	for _, b := range p.bytes[:min(p.index, len(p.bytes))] {
		if b == '\n' {
			line++
			column = 1
		} else {
			column++
		}
	}
	return &SyntaxError{Problem: problem, Line: line, Column: column}
}

func (p *parser) skipBlanks() {
	for p.index < len(p.bytes) {
		switch p.bytes[p.index] {
		case ' ', '\t', '\n', '\r':
			p.index++
		default:
			return
		}
	}
}

func (p *parser) parseValue() (node, error) {
	if p.index >= len(p.bytes) {
		return node{}, p.fail(UnexpectedEnd)
	}
	start := p.index
	switch c := p.bytes[p.index]; {
	case c == '{':
		return p.parseObject()
	case c == '[':
		return p.parseArray()
	case c == '"':
		text, err := p.parseString()
		if err != nil {
			return node{}, err
		}
		return node{start: start, end: p.index, scalar: String(text)}, nil
	case c == 't':
		return p.parseWord("true", Bool(true))
	case c == 'f':
		return p.parseWord("false", Bool(false))
	case c == 'n':
		return p.parseWord("null", Null())
	case c == '-' || (c >= '0' && c <= '9'):
		end := numberEnd(p.bytes, p.index)
		if !isNumber(p.bytes[p.index:end]) {
			return node{}, p.fail(InvalidNumber)
		}
		p.index = end
		return node{start: start, end: end, scalar: Number(string(p.bytes[start:end]))}, nil
	}
	return node{}, p.fail(UnexpectedCharacter)
}

func (p *parser) parseWord(word string, v Value) (node, error) {
	start := p.index
	if string(p.bytes[p.index:min(p.index+len(word), len(p.bytes))]) != word {
		return node{}, p.fail(UnexpectedCharacter)
	}
	p.index += len(word)
	return node{start: start, end: p.index, scalar: v}, nil
}

func (p *parser) enter() error {
	p.depth++
	if p.depth > MaxDepth {
		return ErrTooDeep
	}
	return nil
}

func (p *parser) parseObject() (node, error) {
	if err := p.enter(); err != nil {
		return node{}, err
	}
	defer func() { p.depth-- }()
	start := p.index
	p.index++
	var members []nodeMember
	p.skipBlanks()
	if p.index < len(p.bytes) && p.bytes[p.index] == '}' {
		p.index++
		return node{kind: nodeObject, start: start, end: p.index}, nil
	}
	for {
		p.skipBlanks()
		if p.index >= len(p.bytes) {
			return node{}, p.fail(UnexpectedEnd)
		}
		if p.bytes[p.index] != '"' {
			return node{}, p.fail(ExpectedKey)
		}
		keyStart := p.index
		key, err := p.parseString()
		if err != nil {
			return node{}, err
		}
		keyEnd := p.index
		p.skipBlanks()
		if p.index >= len(p.bytes) {
			return node{}, p.fail(UnexpectedEnd)
		}
		if p.bytes[p.index] != ':' {
			return node{}, p.fail(ExpectedColon)
		}
		p.index++
		p.skipBlanks()
		value, err := p.parseValue()
		if err != nil {
			return node{}, err
		}
		members = append(members, nodeMember{key: key, keyStart: keyStart, keyEnd: keyEnd, value: value})
		p.skipBlanks()
		if p.index >= len(p.bytes) {
			return node{}, p.fail(UnexpectedEnd)
		}
		switch p.bytes[p.index] {
		case ',':
			p.index++
		case '}':
			p.index++
			return node{kind: nodeObject, start: start, end: p.index, members: members}, nil
		default:
			return node{}, p.fail(ExpectedCommaOrEnd)
		}
	}
}

func (p *parser) parseArray() (node, error) {
	if err := p.enter(); err != nil {
		return node{}, err
	}
	defer func() { p.depth-- }()
	start := p.index
	p.index++
	var items []node
	p.skipBlanks()
	if p.index < len(p.bytes) && p.bytes[p.index] == ']' {
		p.index++
		return node{kind: nodeArray, start: start, end: p.index}, nil
	}
	for {
		p.skipBlanks()
		item, err := p.parseValue()
		if err != nil {
			return node{}, err
		}
		items = append(items, item)
		p.skipBlanks()
		if p.index >= len(p.bytes) {
			return node{}, p.fail(UnexpectedEnd)
		}
		switch p.bytes[p.index] {
		case ',':
			p.index++
		case ']':
			p.index++
			return node{kind: nodeArray, start: start, end: p.index, items: items}, nil
		default:
			return node{}, p.fail(ExpectedCommaOrEnd)
		}
	}
}

func (p *parser) parseString() (string, error) {
	p.index++
	var out []byte
	for {
		if p.index >= len(p.bytes) {
			return "", p.fail(UnexpectedEnd)
		}
		b := p.bytes[p.index]
		switch {
		case b == '"':
			p.index++
			return string(out), nil
		case b < 0x20:
			return "", p.fail(ControlCharacterInString)
		case b == '\\':
			p.index++
			if p.index >= len(p.bytes) {
				return "", p.fail(UnexpectedEnd)
			}
			escape := p.bytes[p.index]
			p.index++
			switch escape {
			case '"':
				out = append(out, '"')
			case '\\':
				out = append(out, '\\')
			case '/':
				out = append(out, '/')
			case 'b':
				out = append(out, 0x08)
			case 'f':
				out = append(out, 0x0C)
			case 'n':
				out = append(out, '\n')
			case 'r':
				out = append(out, '\r')
			case 't':
				out = append(out, '\t')
			case 'u':
				r, err := p.parseUnicodeEscape()
				if err != nil {
					return "", err
				}
				out = utf8.AppendRune(out, r)
			default:
				p.index--
				return "", p.fail(InvalidEscape)
			}
		default:
			out = append(out, b)
			p.index++
		}
	}
}

// parseUnicodeEscape reads the code after \u. A surrogate pair becomes one rune; a lone surrogate becomes
// U+FFFD and a following escape is then read on its own.
func (p *parser) parseUnicodeEscape() (rune, error) {
	unit, err := p.hex4()
	if err != nil {
		return 0, err
	}
	switch {
	case unit >= 0xD800 && unit <= 0xDBFF:
		if p.index+1 < len(p.bytes) && p.bytes[p.index] == '\\' && p.bytes[p.index+1] == 'u' {
			save := p.index
			p.index += 2
			low, err := p.hex4()
			if err != nil {
				return 0, err
			}
			if low >= 0xDC00 && low <= 0xDFFF {
				return rune(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)), nil
			}
			p.index = save
		}
		return utf8.RuneError, nil
	case unit >= 0xDC00 && unit <= 0xDFFF:
		return utf8.RuneError, nil
	}
	return rune(unit), nil
}

func (p *parser) hex4() (uint32, error) {
	if p.index+4 > len(p.bytes) {
		return 0, p.fail(UnexpectedEnd)
	}
	var value uint32
	for range 4 {
		digit, ok := hexValue(p.bytes[p.index])
		if !ok {
			return 0, p.fail(InvalidEscape)
		}
		value = value<<4 | digit
		p.index++
	}
	return value, nil
}

func hexValue(b byte) (uint32, bool) {
	switch {
	case b >= '0' && b <= '9':
		return uint32(b - '0'), true
	case b >= 'a' && b <= 'f':
		return uint32(b-'a') + 10, true
	case b >= 'A' && b <= 'F':
		return uint32(b-'A') + 10, true
	}
	return 0, false
}

// numberEnd is the end of a run of number characters; isNumber then checks the grammar.
func numberEnd(bytes []byte, start int) int {
	end := start
	for end < len(bytes) && strings.IndexByte("+-.0123456789eE", bytes[end]) >= 0 {
		end++
	}
	return end
}

// isNumber reports whether text matches -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?
func isNumber(text []byte) bool {
	i := 0
	digits := func() int {
		start := i
		for i < len(text) && text[i] >= '0' && text[i] <= '9' {
			i++
		}
		return i - start
	}
	if i < len(text) && text[i] == '-' {
		i++
	}
	if i >= len(text) {
		return false
	}
	if text[i] == '0' {
		i++
	} else if digits() == 0 {
		return false
	}
	if i < len(text) && text[i] == '.' {
		i++
		if digits() == 0 {
			return false
		}
	}
	if i < len(text) && (text[i] == 'e' || text[i] == 'E') {
		i++
		if i < len(text) && (text[i] == '+' || text[i] == '-') {
			i++
		}
		if digits() == 0 {
			return false
		}
	}
	return i == len(text)
}
