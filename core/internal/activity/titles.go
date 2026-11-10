package activity

import (
	"strings"
	"unicode"

	"spacevibe.dev/core/internal/textjs"
)

// Session titles (SessionTitles.swift): pure helpers over text. Swift compared Strings by canonical equivalence and
// Characters; these compare bytes and code points (plan H14). That only differs for a prefix or tag followed by a
// combining mark, such as "<" + U+0338.

const titleMax = 80

var junkTags = []string{"<command-name>", "<local-command", "<system-reminder", "<task-notification"}

var junkWords = map[string]bool{"warmup": true, "untitled": true, "new session": true, "no title": true, "claude session": true, "codex session": true}

// isJunk is true for text that is not a title: empty, a slash command, lifecycle or caveat text.
func isJunk(text string) bool {
	t := textjs.Squash(text)
	if textjs.UTF16Length(t) < 2 || !strings.ContainsFunc(t, isLetterOrNumber) {
		return true
	}
	if isSlashCommand(t) || strings.HasPrefix(t, "<") {
		return true
	}
	for _, tag := range junkTags {
		if strings.Contains(t, tag) {
			return true
		}
	}
	lower := swiftLower(t)
	if strings.HasPrefix(lower, "caveat:") || strings.HasPrefix(lower, "[request interrupted") || strings.HasPrefix(lower, "# agents.md instructions") {
		return true
	}
	return junkWords[lower]
}

// swiftLower is String.lowercased(): the full mapping, where U+0130 becomes "i" and a combining dot.
func swiftLower(s string) string {
	return strings.ToLower(strings.ReplaceAll(s, "İ", "i̇"))
}

func isLetterOrNumber(r rune) bool { return unicode.IsLetter(r) || unicode.IsNumber(r) }

// isSlashCommand is `/^\/[\w:-]+(\s|$)/`: "/clear", "/model opus". A path such as "/Users/me/x" is not a command.
func isSlashCommand(t string) bool {
	if !strings.HasPrefix(t, "/") {
		return false
	}
	sawName := false
	for _, r := range t[1:] {
		word := (r >= '0' && r <= '9') || (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || r == '_' || r == ':' || r == '-'
		if word {
			sawName = true
			continue
		}
		return sawName && textjs.IsJSSpace(r)
	}
	return sawName
}

// cleanTitle is a single line, at most 80 UTF-16 units, ending in an ellipsis when cut.
func cleanTitle(text string) string {
	t := textjs.Squash(text)
	if textjs.UTF16Length(t) > titleMax {
		return textjs.Prefix(t, titleMax-1) + "…"
	}
	return t
}

// pickTitle is the first candidate that is not junk, else `YYYY-MM-DD · short id`. An empty candidate is junk, so
// it stands for the Swift nil. startedAt is epoch milliseconds.
func pickTitle(candidates []string, startedAt *float64, id string) string {
	for _, c := range candidates {
		if c != "" && !isJunk(c) {
			return cleanTitle(c)
		}
	}
	day := textjs.UnknownDate
	if startedAt != nil {
		if ms, ok := textjs.BoundedTimestamp(*startedAt); ok {
			day = textjs.IsoDay(ms)
		}
	}
	return day + " · " + shortID(id)
}

// shortID is the first 8 characters of an id; a "pid N" id is whole, because cutting it names another process.
func shortID(id string) string {
	if strings.HasPrefix(id, "pid ") {
		return id
	}
	return textjs.Prefix(id, 8)
}
