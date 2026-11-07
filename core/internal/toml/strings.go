package toml

import "unicode/utf8"

// parseLiteralString reads '...' at p.i; no escapes, no newline.
func (p *parser) parseLiteralString() (string, bool) {
	p.i++
	start := p.i
	for p.i < len(p.b) && p.b[p.i] != '\'' {
		if p.b[p.i] == '\n' {
			return "", false
		}
		p.i++
	}
	if p.i >= len(p.b) {
		return "", false
	}
	s := string(p.b[start:p.i])
	p.i++
	return s, true
}

// parseBasicString reads "..." at p.i with escapes; no newline.
func (p *parser) parseBasicString() (string, bool) {
	p.i++
	out := []byte{}
	for p.i < len(p.b) {
		c := p.b[p.i]
		switch c {
		case '"':
			p.i++
			return string(out), true
		case '\n':
			return "", false
		case '\\':
			if !p.appendEscape(&out) {
				return "", false
			}
		default:
			out = append(out, c)
			p.i++
		}
	}
	return "", false
}

// parseMultiline reads triple-quoted strings (basic or literal). A newline right after the
// opening is dropped; up to two quotes may precede the closing.
func (p *parser) parseMultiline(quote byte, literal bool) (string, bool) {
	p.i += 3
	if p.i+1 < len(p.b) && p.b[p.i] == '\r' && p.b[p.i+1] == '\n' {
		p.i += 2
	} else if p.i < len(p.b) && p.b[p.i] == '\n' {
		p.i++
	}
	out := []byte{}
	for p.i < len(p.b) {
		c := p.b[p.i]
		if c == quote && p.i+2 < len(p.b) && p.b[p.i+1] == quote && p.b[p.i+2] == quote {
			extra := 0
			for extra < 2 && p.i+3+extra < len(p.b) && p.b[p.i+3+extra] == quote {
				extra++
			}
			for range extra {
				out = append(out, quote)
			}
			p.i += 3 + extra
			return string(out), true
		}
		if !literal && c == '\\' {
			// A backslash at the end of a line swallows the newline and the blanks that follow.
			look := p.i + 1
			for look < len(p.b) && (p.b[look] == ' ' || p.b[look] == '\t' || p.b[look] == '\r') {
				look++
			}
			if look < len(p.b) && p.b[look] == '\n' {
				p.i = look + 1
				for p.i < len(p.b) && (p.b[p.i] == ' ' || p.b[p.i] == '\t' || p.b[p.i] == '\n' || p.b[p.i] == '\r') {
					p.i++
				}
				continue
			}
			if !p.appendEscape(&out) {
				return "", false
			}
			continue
		}
		out = append(out, c)
		p.i++
	}
	return "", false
}

// appendEscape reads \x at p.i. An unknown escape is kept as written rather than failing the file.
func (p *parser) appendEscape(out *[]byte) bool {
	p.i++
	if p.i >= len(p.b) {
		return false
	}
	code := p.b[p.i]
	p.i++
	switch code {
	case 'b':
		*out = append(*out, 0x08)
	case 't':
		*out = append(*out, 0x09)
	case 'n':
		*out = append(*out, 0x0A)
	case 'f':
		*out = append(*out, 0x0C)
	case 'r':
		*out = append(*out, 0x0D)
	case 'e':
		*out = append(*out, 0x1B)
	case '"':
		*out = append(*out, '"')
	case '\\':
		*out = append(*out, '\\')
	case 'u', 'U':
		length := 4
		if code == 'U' {
			length = 8
		}
		if p.i+length > len(p.b) {
			return false
		}
		scalar, ok := parseScalar(p.b[p.i : p.i+length])
		if !ok {
			return false
		}
		p.i += length
		*out = utf8.AppendRune(*out, scalar)
	default:
		*out = append(*out, '\\', code)
	}
	return true
}

// parseScalar reads hex digits as a Unicode scalar value the way Swift's
// UInt32(_:radix: 16) and Unicode.Scalar(_:) do: one leading "+" is accepted, "-" only before
// zero, and surrogates and values above U+10FFFF are refused.
func parseScalar(hex []byte) (rune, bool) {
	negative := false
	if len(hex) > 0 && (hex[0] == '+' || hex[0] == '-') {
		negative = hex[0] == '-'
		hex = hex[1:]
	}
	if len(hex) == 0 {
		return 0, false
	}
	var value uint64
	for _, c := range hex {
		var d byte
		switch {
		case c >= '0' && c <= '9':
			d = c - '0'
		case c >= 'a' && c <= 'f':
			d = c - 'a' + 10
		case c >= 'A' && c <= 'F':
			d = c - 'A' + 10
		default:
			return 0, false
		}
		value = value<<4 | uint64(d)
	}
	if negative && value != 0 {
		return 0, false
	}
	if value > utf8.MaxRune || !utf8.ValidRune(rune(value)) {
		return 0, false
	}
	return rune(value), true
}
