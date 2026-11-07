package ojson

import (
	"bytes"
	"fmt"
	"strings"
)

// style is how a document spells things, so new text looks like the old text.
type style struct {
	unit      string
	newline   string
	colon     string
	multiline bool
}

func (s style) comma() string {
	if strings.HasSuffix(s.colon, " ") {
		return ", "
	}
	return ","
}

// newStyle reads the style of a document.
func newStyle(d *Document) style {
	src := d.bytes
	start, end := d.tree.start, d.tree.end
	emptyRoot := false
	switch d.tree.kind {
	case nodeObject:
		emptyRoot = len(d.tree.members) == 0
	case nodeArray:
		emptyRoot = len(d.tree.items) == 0
	}
	var s style
	// A fresh {} followed by a newline is a pretty-printed file waiting for its first key.
	s.multiline = d.hasNewline(start, end) || (emptyRoot && bytes.IndexByte(src, '\n') >= 0)
	s.newline = "\n"
	for i := 0; i+1 < len(src); i++ {
		if src[i] == '\r' && src[i+1] == '\n' {
			s.newline = "\r\n"
			break
		}
	}

	// The first indented line inside the root is one level deep, so its blanks are one unit.
	s.unit = "  "
	for scan := start; scan < end; {
		rel := bytes.IndexByte(src[scan:end], '\n')
		if rel < 0 {
			break
		}
		lineStart := scan + rel + 1
		blankEnd := lineStart
		for blankEnd < end && (src[blankEnd] == ' ' || src[blankEnd] == '\t') {
			blankEnd++
		}
		if blankEnd > lineStart && blankEnd < end && src[blankEnd] != '\n' && src[blankEnd] != '\r' {
			s.unit = string(src[lineStart:blankEnd])
			break
		}
		scan = lineStart
	}

	if sep, ok := d.tree.firstMemberSeparator(src); ok {
		s.colon = sep
	} else if s.multiline {
		s.colon = ": "
	} else {
		s.colon = ":"
	}
	return s
}

// quote writes a JSON string. It escapes only what JSON requires: no HTML escapes, no U+2028/2029 escapes.
func (s style) quote(str string) string {
	var out strings.Builder
	out.WriteByte('"')
	for _, r := range str { // invalid UTF-8 becomes U+FFFD, as a Swift String would hold it
		switch r {
		case '"':
			out.WriteString(`\"`)
		case '\\':
			out.WriteString(`\\`)
		case '\n':
			out.WriteString(`\n`)
		case '\r':
			out.WriteString(`\r`)
		case '\t':
			out.WriteString(`\t`)
		case '\b':
			out.WriteString(`\b`)
		case '\f':
			out.WriteString(`\f`)
		default:
			if r < 0x20 {
				fmt.Fprintf(&out, `\u%04x`, r)
			} else {
				out.WriteRune(r)
			}
		}
	}
	out.WriteByte('"')
	return out.String()
}

// render writes a value. expanded puts each member and element on its own line, indented from base.
func (s style) render(v Value, base string, expanded bool) (string, error) {
	switch v.kind {
	case KindNull:
		return "null", nil
	case KindBool:
		if v.b {
			return "true", nil
		}
		return "false", nil
	case KindNumber:
		if !isNumber([]byte(v.s)) {
			return "", ErrInvalidValue
		}
		return v.s, nil
	case KindString:
		return s.quote(v.s), nil
	}
	inner := base + s.unit
	childBase := base
	if expanded {
		childBase = inner
	}
	var parts []string
	var open, closing string
	switch v.kind {
	case KindArray:
		if len(v.items) == 0 {
			return "[]", nil
		}
		open, closing = "[", "]"
		for _, it := range v.items {
			text, err := s.render(it, childBase, expanded)
			if err != nil {
				return "", err
			}
			parts = append(parts, text)
		}
	default:
		if len(v.members) == 0 {
			return "{}", nil
		}
		open, closing = "{", "}"
		for _, m := range v.members {
			text, err := s.render(m.Value, childBase, expanded)
			if err != nil {
				return "", err
			}
			parts = append(parts, s.quote(m.Key)+s.colon+text)
		}
	}
	if !expanded {
		return open + strings.Join(parts, s.comma()) + closing, nil
	}
	for i := range parts {
		parts[i] = inner + parts[i]
	}
	return open + s.newline + strings.Join(parts, ","+s.newline) + s.newline + base + closing, nil
}

// Pretty is the text of a value that has no source file yet (the journal, a new settings file): two-space
// indent, LF, and a trailing newline.
func Pretty(v Value) (string, error) { return PrettyStyled(v, "  ", "\n", true) }

// PrettyStyled is Pretty with a chosen indent and newline.
func PrettyStyled(v Value, indent, newline string, trailingNewline bool) (string, error) {
	s := style{unit: indent, newline: newline, colon: ": ", multiline: true}
	text, err := s.render(v, "", true)
	if err != nil {
		return "", err
	}
	if trailingNewline {
		text += newline
	}
	return text, nil
}
