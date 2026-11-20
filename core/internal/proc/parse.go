package proc

import (
	"strings"

	"spacevibe.dev/core/internal/textjs"
)

// ICU (NSRegularExpression) and Go differ on three things these patterns touch: \s is the Unicode
// White_Space set, `.` stops at any line terminator (\n \v \f \r U+0085 U+2028 U+2029), and `$` also matches
// before one final line terminator. The classes below take the ICU sets from textjs (the same ones activity
// uses) and finalTerminator handles `$`.
const (
	icuSpace = textjs.ICUSpaceSet
	icuDot   = `[^` + textjs.ICUTermSet + `]`
)

// finalTerminator drops one trailing line terminator, which ICU's `$` accepts before the end.
func finalTerminator(s string) string {
	if strings.HasSuffix(s, "\r\n") {
		return s[:len(s)-2]
	}
	for _, t := range []string{"\n", "\v", "\f", "\r", "\u0085", "\u2028", "\u2029"} {
		if strings.HasSuffix(s, t) {
			return s[:len(s)-len(t)]
		}
	}
	return s
}

// startFields is how many whitespace-separated words `ps lstart` prints ("Mon Nov  2 11:58:00 2026").
const startFields = 5

// ParseIdentity reads `ps -o lstart=,comm=` output for one pid: the five start words, then the executable
// path, of which only the basename is kept (so a moved install does not change the name). ok is false when
// the start words or the command are missing.
func ParseIdentity(psOutput string) (Identity, bool) {
	fields := strings.Fields(psOutput)
	if len(fields) <= startFields {
		return Identity{}, false
	}
	command := strings.Join(fields[startFields:], " ")
	name := command
	if i := strings.LastIndexAny(command, `/\`); i >= 0 {
		name = command[i+1:]
	}
	if name == "" {
		return Identity{}, false
	}
	return Identity{Start: strings.Join(fields[:startFields], " "), Name: name}, true
}
