package mutate

import (
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"

	"spacevibe.dev/core/internal/inventory"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/textjs"
	"spacevibe.dev/core/internal/toml"
	"spacevibe.dev/core/internal/usage"
)

// Text formats of the Node core, spelled the same way: JSON.stringify strings and the agent files of both CLIs
// (MutateText.swift).

// quote is JSON.stringify(text): a double-quoted string, which is also valid YAML and TOML for what the CLIs read.
func quote(text string) string {
	out, err := ojson.PrettyStyled(ojson.String(text), "  ", "\n", false)
	if err != nil {
		return `""`
	}
	return out
}

// tomlQuote is quote for a TOML basic string. JSON leaves U+007F (DEL) as it is, and TOML forbids it unescaped
// (G-fix.17), so it is written as \u007f. Every other control character is already escaped by JSON.stringify.
func tomlQuote(text string) string { return strings.ReplaceAll(quote(text), "\x7f", `\u007f`) }

// yamlValue is the description value of a generated header: one line, quoted.
func yamlValue(text string) string { return quote(textjs.Squash(text)) }

// agentText is a new agent file in the format of its CLI: markdown with a header for Claude Code, TOML for Codex.
func agentText(cli usage.CLI, name, description, instructions string) string {
	body := textjs.Trim(instructions)
	if cli == inventory.Claude {
		return "---\nname: " + name + "\ndescription: " + yamlValue(description) + "\n---\n\n" + body + "\n"
	}
	return "name = " + tomlQuote(name) + "\ndescription = " + tomlQuote(description) + "\ndeveloper_instructions = " + tomlQuote(body) + "\n"
}

func skillText(name, description, body string) string {
	return "---\nname: " + name + "\ndescription: " + yamlValue(description) + "\n---\n\n" + textjs.Trim(body) + "\n"
}

// agentFields is what an agent file says, as the Node copy reads it: markdown header plus body, or the TOML keys.
func agentFields(isTOML bool, text string) (description, instructions string) {
	if isTOML {
		return tomlDescription(text), tomlInstructions(text)
	}
	return inventory.ParseFrontmatter(text)["description"], stripHeader(text)
}

// tomlDescription is the first string assignment of description, in any table, as the Node regex finds it
// (Inventory.tomlFields).
func tomlDescription(text string) string {
	for _, e := range toml.Read(text).Entries {
		if len(e.KeyPath) == 1 && e.KeyPath[0] == "description" && e.Value != nil {
			if s, ok := e.Value.AsString(); ok {
				return s
			}
		}
	}
	return ""
}

// ICU (NSRegularExpression) rules the two developer_instructions patterns depend on. RE2 has no backreference and
// differs on \s, ^ and . (see the trap list in the Go-port plan), so the two patterns are matched by hand:
//
//	^developer_instructions\s*=\s*("""|''')([\s\S]*?)\1     (anchorsMatchLines)
//	^developer_instructions\s*=\s*("(?:[^"\\]|\\.)*")        (anchorsMatchLines)

func isLineTerminator(r rune) bool {
	switch r {
	case '\n', '\r', '\v', '\f', 0x85, 0x2028, 0x2029:
		return true
	}
	return false
}

// lineStarts are the offsets where ^ matches in multiline mode: the start, and after each terminator ("\r\n" is one).
func lineStarts(text string) []int {
	starts := []int{0}
	for i, r := range text {
		if !isLineTerminator(r) {
			continue
		}
		end := i + utf8.RuneLen(r)
		if r == '\r' && end < len(text) && text[end] == '\n' {
			continue
		}
		starts = append(starts, end)
	}
	return starts
}

func skipSpace(text string, i int) int {
	for i < len(text) {
		r, size := utf8.DecodeRuneInString(text[i:])
		if !unicode.IsSpace(r) {
			break
		}
		i += size
	}
	return i
}

// afterEquals is the offset of the value after "developer_instructions\s*=\s*" at a line start, or -1.
func afterEquals(text string, start int) int {
	const key = "developer_instructions"
	if !strings.HasPrefix(text[start:], key) {
		return -1
	}
	i := skipSpace(text, start+len(key))
	if i >= len(text) || text[i] != '=' {
		return -1
	}
	return skipSpace(text, i+1)
}

// tomlInstructions is developer_instructions of a Codex agent: a triple-quoted block as written (one leading
// newline dropped), or a one-line string. Escapes inside a block are kept as written, like the Node regex does.
func tomlInstructions(text string) string {
	starts := lineStarts(text)
	for _, start := range starts {
		i := afterEquals(text, start)
		if i < 0 {
			continue
		}
		for _, delim := range []string{`"""`, `'''`} {
			if !strings.HasPrefix(text[i:], delim) {
				continue
			}
			if end := strings.Index(text[i+3:], delim); end >= 0 {
				return strings.TrimPrefix(text[i+3:i+3+end], "\n")
			}
		}
	}
	for _, start := range starts {
		i := afterEquals(text, start)
		if i < 0 || i >= len(text) || text[i] != '"' {
			continue
		}
		if end := quotedEnd(text, i); end > 0 {
			return unquote(text[i:end])
		}
	}
	return ""
}

// quotedEnd is the offset after the closing quote of the "(?:[^"\\]|\\.)*" string that starts at i, or -1 when the
// string is not closed on the way (a backslash must be followed by a character that is not a line terminator).
func quotedEnd(text string, i int) int {
	for j := i + 1; j < len(text); {
		r, size := utf8.DecodeRuneInString(text[j:])
		switch {
		case r == '"':
			return j + 1
		case r == '\\':
			if j+size >= len(text) {
				return -1
			}
			next, nextSize := utf8.DecodeRuneInString(text[j+size:])
			if isLineTerminator(next) {
				return -1
			}
			j += size + nextSize
		default:
			j += size
		}
	}
	return -1
}

// unquote reads a YAML-ish scalar: "double" (JSON escapes), 'single' (two single quotes make one), or plain text
// (Frontmatter.unquote).
func unquote(value string) string {
	t := strings.TrimFunc(value, unicode.IsSpace)
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

var headerRE = regexp.MustCompile(`\A---\r?\n[\s\S]*?\r?\n---\r?\n?`)

// stripHeader is the text after the --- header, or the whole text when there is none.
func stripHeader(text string) string {
	loc := headerRE.FindStringIndex(text)
	if loc == nil {
		return text
	}
	return text[loc[1]:]
}
