package inventory

import (
	"bytes"
	"strings"
	"unicode"
	"unicode/utf8"

	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/textjs"
)

// ParseFrontmatter reads the "---" header of a SKILL.md or an agent .md file. Flat "key: value" lines only,
// values as text, ">" and "|" block scalars joined (folded with a space, literal with newlines). It is not a
// YAML parser: lists and nested maps are not understood and their lines are ignored. The result is empty when
// the text has no header; with a repeated key the last one wins. Ported from Frontmatter.swift.
//
// Difference to Swift, which counts grapheme clusters where it drops the first and last character of a
// malformed quoted value: this drops one code point.
func ParseFrontmatter(text string) map[string]string {
	out := map[string]string{}
	lines, ok := headerLines(text)
	if !ok {
		return out
	}
	for index := 0; index < len(lines); index++ {
		key, raw, ok := keyValue(lines[index])
		if !ok {
			continue
		}
		marker := trimSpace(raw)
		if isBlockMarker(marker) {
			var block []string
			for index+1 < len(lines) && (lines[index+1] == "" || startsWithSpace(lines[index+1])) {
				index++
				block = append(block, trimSpace(lines[index]))
			}
			sep := "\n"
			if strings.HasPrefix(marker, ">") {
				sep = " "
			}
			out[key] = trimSpace(strings.Join(block, sep))
		} else {
			out[key] = unquote(raw)
		}
	}
	return out
}

// trimSpace trims Unicode White_Space, which is Foundation's whitespacesAndNewlines.
func trimSpace(s string) string { return strings.TrimFunc(s, unicode.IsSpace) }

// unquote reads a YAML-ish scalar: "double" (JSON escapes), 'single' (” is a quote), or plain text.
func unquote(value string) string {
	t := trimSpace(value)
	if strings.HasPrefix(t, `"`) {
		if doc, err := ojson.ParseString(t); err == nil {
			if s, ok := doc.Root().StringValue(); ok {
				return s
			}
		}
		return dropEnds(t)
	}
	if strings.HasPrefix(t, "'") && strings.HasSuffix(t, "'") && utf8.RuneCountInString(t) >= 2 {
		return strings.ReplaceAll(dropEnds(t), "''", "'")
	}
	return t
}

// dropEnds is dropFirst().dropLast() by code point.
func dropEnds(s string) string {
	_, first := utf8.DecodeRuneInString(s)
	s = s[first:]
	_, last := utf8.DecodeLastRuneInString(s)
	return s[:len(s)-last]
}

// headerLines are the lines between the opening "---" and the first line that starts with "---", or false
// without a header. Works on bytes, as the Swift port does.
func headerLines(text string) ([]string, bool) {
	b := []byte(text)
	var start int
	switch {
	case bytes.HasPrefix(b, []byte("---\n")):
		start = 4
	case bytes.HasPrefix(b, []byte("---\r\n")):
		start = 5
	default:
		return nil, false
	}
	fence := []byte("\n---")
	end, found := start, false
	for end+len(fence) <= len(b) {
		if b[end] == '\n' && bytes.Equal(b[end:end+len(fence)], fence) {
			found = true
			break
		}
		end++
	}
	if !found {
		return nil, false
	}
	if end > start && b[end-1] == '\r' {
		end--
	}
	if end < start {
		end = start
	}
	var lines []string
	for _, line := range bytes.Split(b[start:end], []byte{'\n'}) {
		line = bytes.TrimSuffix(line, []byte{'\r'})
		lines = append(lines, textjs.Repair(string(line)))
	}
	return lines, true
}

// keyValue is ^([A-Za-z][\w-]*):\s*(.*)$ with an ASCII \w and a Unicode \s.
func keyValue(line string) (key, value string, ok bool) {
	if line == "" || !isASCIILetter(line[0]) {
		return "", "", false
	}
	end := 1
	for end < len(line) && isKeyByte(line[end]) {
		end++
	}
	if end >= len(line) || line[end] != ':' {
		return "", "", false
	}
	return line[:end], strings.TrimLeftFunc(line[end+1:], unicode.IsSpace), true
}

func isASCIILetter(b byte) bool { return b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' }

func isKeyByte(b byte) bool { return isASCIILetter(b) || b >= '0' && b <= '9' || b == '_' || b == '-' }

// isBlockMarker: ">" or "|", optionally followed by one "+" or "-".
func isBlockMarker(text string) bool {
	if text == "" || (text[0] != '>' && text[0] != '|') {
		return false
	}
	rest := text[1:]
	return rest == "" || rest == "+" || rest == "-"
}

func startsWithSpace(line string) bool {
	r, size := utf8.DecodeRuneInString(line)
	return size > 0 && unicode.IsSpace(r)
}
