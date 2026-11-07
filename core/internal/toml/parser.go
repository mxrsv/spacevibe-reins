package toml

import (
	"errors"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

// maxDepth bounds open arrays and inline tables. Deeper than this the value is unreadable (nil),
// so the line is skipped instead of recursing without limit. Real configs nest two or three levels.
const maxDepth = 64

type parser struct {
	b          []byte
	i          int
	skipped    int
	depth      int
	lineStarts []int
}

func (p *parser) indexLines() {
	p.lineStarts = []int{0}
	for off, c := range p.b {
		if c == '\n' {
			p.lineStarts = append(p.lineStarts, off+1)
		}
	}
}

// lineAt returns the 1-based line of a byte offset.
func (p *parser) lineAt(offset int) int {
	return sort.Search(len(p.lineStarts), func(k int) bool { return p.lineStarts[k] > offset })
}

func (p *parser) run() Document {
	table := []string{}
	inArrayTable := false
	doc := Document{Entries: []Entry{}, Tables: []TableHeader{}}
	for {
		p.skipTrivia()
		if p.i >= len(p.b) {
			break
		}
		if p.b[p.i] == '[' {
			if header, ok := p.parseHeader(); ok {
				doc.Tables = append(doc.Tables, header)
				table = header.Path
				inArrayTable = header.IsArray
			} else {
				p.skipLine(true)
			}
			continue
		}
		start := p.i
		keyPath, ok := p.parseKeyPath()
		if !ok {
			p.skipLine(true)
			continue
		}
		p.skipSpaces()
		if p.i >= len(p.b) || p.b[p.i] != '=' {
			p.skipLine(true)
			continue
		}
		p.i++
		p.skipSpaces()
		entry := Entry{Table: table, KeyPath: keyPath, Line: p.lineAt(start), InArrayTable: inArrayTable}
		if v, ok := p.parseValue(); ok {
			entry.Value = &v
			p.skipRestOfLine()
		} else {
			p.skipLine(true)
		}
		doc.Entries = append(doc.Entries, entry)
	}
	doc.SkippedLines = p.skipped
	return doc
}

// Lines

func (p *parser) skipSpaces() {
	for p.i < len(p.b) && (p.b[p.i] == ' ' || p.b[p.i] == '\t') {
		p.i++
	}
}

func (p *parser) skipComment() {
	if p.i < len(p.b) && p.b[p.i] == '#' {
		for p.i < len(p.b) && p.b[p.i] != '\n' {
			p.i++
		}
	}
}

func (p *parser) skipTrivia() {
	for p.i < len(p.b) {
		switch c := p.b[p.i]; {
		case c == ' ' || c == '\t' || c == '\n' || c == '\r':
			p.i++
		case c == '#':
			p.skipComment()
		default:
			return
		}
	}
}

func (p *parser) skipLine(count bool) {
	for p.i < len(p.b) && p.b[p.i] != '\n' {
		p.i++
	}
	if count {
		p.skipped++
	}
}

// skipRestOfLine runs after a value: blanks and a comment are fine; anything else is garbage on
// the line and is skipped.
func (p *parser) skipRestOfLine() {
	p.skipSpaces()
	p.skipComment()
	if p.i < len(p.b) && p.b[p.i] != '\n' && p.b[p.i] != '\r' {
		p.skipLine(true)
	}
}

// Headers and keys

func (p *parser) parseHeader() (TableHeader, bool) {
	isArray := p.i+1 < len(p.b) && p.b[p.i+1] == '['
	if isArray {
		p.i += 2
	} else {
		p.i++
	}
	path, ok := p.parseKeyPath()
	if !ok {
		return TableHeader{}, false
	}
	p.skipSpaces()
	closers := 1
	if isArray {
		closers = 2
	}
	for range closers {
		if p.i >= len(p.b) || p.b[p.i] != ']' {
			return TableHeader{}, false
		}
		p.i++
	}
	p.skipRestOfLine()
	return TableHeader{Path: path, IsArray: isArray}, true
}

func (p *parser) parseKeyPath() ([]string, bool) {
	parts := []string{}
	for {
		p.skipSpaces()
		if p.i >= len(p.b) {
			return nil, false
		}
		switch p.b[p.i] {
		case '"':
			s, ok := p.parseBasicString()
			if !ok {
				return nil, false
			}
			parts = append(parts, s)
		case '\'':
			s, ok := p.parseLiteralString()
			if !ok {
				return nil, false
			}
			parts = append(parts, s)
		default:
			start := p.i
			for p.i < len(p.b) && isBare(p.b[p.i]) {
				p.i++
			}
			if p.i == start {
				return nil, false
			}
			parts = append(parts, string(p.b[start:p.i]))
		}
		p.skipSpaces()
		if p.i < len(p.b) && p.b[p.i] == '.' {
			p.i++
			continue
		}
		return parts, true
	}
}

func isBare(c byte) bool {
	return c >= '0' && c <= '9' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c == '_' || c == '-'
}

// Values

func (p *parser) parseValue() (Value, bool) {
	if p.i >= len(p.b) {
		return Value{}, false
	}
	switch p.b[p.i] {
	case '"':
		if p.has(`"""`) {
			return stringValue(p.parseMultiline('"', false))
		}
		return stringValue(p.parseBasicString())
	case '\'':
		if p.has("'''") {
			return stringValue(p.parseMultiline('\'', true))
		}
		return stringValue(p.parseLiteralString())
	case '[':
		return p.parseArray()
	case '{':
		return p.parseInlineTable()
	}
	return p.parseBare()
}

func stringValue(s string, ok bool) (Value, bool) {
	return Value{Kind: KindString, Str: s}, ok
}

func (p *parser) has(text string) bool {
	return p.i+len(text) <= len(p.b) && string(p.b[p.i:p.i+len(text)]) == text
}

func isBareEnd(c byte) bool {
	switch c {
	case ' ', '\t', '\n', '\r', ',', ']', '}', '#':
		return true
	}
	return false
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func (p *parser) parseBare() (Value, bool) {
	start := p.i
	for p.i < len(p.b) && !isBareEnd(p.b[p.i]) {
		p.i++
	}
	if p.i <= start {
		return Value{}, false
	}
	token := string(p.b[start:p.i])
	// A datetime may hold one space between date and time.
	if utf8.RuneCountInString(token) == 10 && strings.Contains(token, "-") &&
		p.i+1 < len(p.b) && p.b[p.i] == ' ' && isDigit(p.b[p.i+1]) {
		save := p.i
		p.i++
		timeStart := p.i
		for p.i < len(p.b) && !isBareEnd(p.b[p.i]) {
			p.i++
		}
		if t := string(p.b[timeStart:p.i]); strings.Contains(t, ":") {
			token += " " + t
		} else {
			p.i = save
		}
	}
	return classifyBare(token), true
}

// classifyBare turns a bare token into a bool, integer, float or, failing that, a raw token.
func classifyBare(token string) Value {
	switch token {
	case "true":
		return Value{Kind: KindBool, Bool: true}
	case "false":
		return Value{Kind: KindBool}
	}
	digits := strings.ReplaceAll(token, "_", "")
	if n, err := strconv.ParseInt(digits, 10, 64); err == nil {
		return Value{Kind: KindInteger, Int: n}
	}
	for _, r := range [...]struct {
		prefix string
		base   int
	}{{"0x", 16}, {"0o", 8}, {"0b", 2}} {
		if strings.HasPrefix(digits, r.prefix) {
			if n, err := strconv.ParseInt(digits[2:], r.base, 64); err == nil {
				return Value{Kind: KindInteger, Int: n}
			}
		}
	}
	if strings.ContainsAny(digits, ".eE") && !strings.HasSuffix(digits, ".") {
		if f, ok := parseFloat(digits); ok {
			return Value{Kind: KindFloat, Float: f}
		}
	}
	return Value{Kind: KindRaw, Str: token}
}

// parseFloat reads what Swift's Double(String) reads: decimal and C-style hex floats (the
// binary exponent is optional there, but Go requires it), and an out of range value as infinity
// or zero rather than a failure.
func parseFloat(s string) (float64, bool) {
	// Swift hands the text to C strtod, so an embedded NUL ends the number there.
	s, _, _ = strings.Cut(s, "\x00")
	if strings.HasPrefix(strings.TrimLeft(s, "+-"), "0X") {
		return 0, false // Swift reads only a lowercase 0x prefix
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil && !errors.Is(err, strconv.ErrRange) && isHexFloatWithoutExponent(s) {
		f, err = strconv.ParseFloat(s+"p0", 64)
	}
	if err == nil || errors.Is(err, strconv.ErrRange) {
		return f, true
	}
	return 0, false
}

func isHexFloatWithoutExponent(s string) bool {
	s = strings.TrimLeft(s, "+-")
	return len(s) > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') && !strings.ContainsAny(s, "pP")
}

func (p *parser) parseArray() (Value, bool) {
	if p.depth >= maxDepth {
		return Value{}, false
	}
	p.depth++
	defer func() { p.depth-- }()
	p.i++
	items := []Value{}
	for {
		p.skipTrivia()
		if p.i >= len(p.b) {
			return Value{}, false
		}
		if p.b[p.i] == ']' {
			p.i++
			return Value{Kind: KindArray, Items: items}, true
		}
		item, ok := p.parseValue()
		if !ok {
			return Value{}, false
		}
		items = append(items, item)
		p.skipTrivia()
		if p.i >= len(p.b) {
			return Value{}, false
		}
		if p.b[p.i] == ',' {
			p.i++
		} else if p.b[p.i] != ']' {
			return Value{}, false
		}
	}
}

func (p *parser) parseInlineTable() (Value, bool) {
	if p.depth >= maxDepth {
		return Value{}, false
	}
	p.depth++
	defer func() { p.depth-- }()
	p.i++
	pairs := []Pair{}
	for {
		p.skipTrivia()
		if p.i >= len(p.b) {
			return Value{}, false
		}
		if p.b[p.i] == '}' {
			p.i++
			return Value{Kind: KindTable, Pairs: pairs}, true
		}
		path, ok := p.parseKeyPath()
		if !ok {
			return Value{}, false
		}
		p.skipSpaces()
		if p.i >= len(p.b) || p.b[p.i] != '=' {
			return Value{}, false
		}
		p.i++
		p.skipSpaces()
		value, ok := p.parseValue()
		if !ok {
			return Value{}, false
		}
		pairs = append(pairs, Pair{Key: join(path), Value: value})
		p.skipTrivia()
		if p.i >= len(p.b) {
			return Value{}, false
		}
		if p.b[p.i] == ',' {
			p.i++
		} else if p.b[p.i] != '}' {
			return Value{}, false
		}
	}
}

func join(parts []string) string { return strings.Join(parts, ".") }
