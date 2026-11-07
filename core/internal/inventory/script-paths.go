package inventory

import (
	"regexp"
	"slices"
	"strings"
)

// spaceRanges is ICU's \s (Unicode White_Space) spelled out for RE2, whose \s is ASCII only.
const spaceRanges = `\t-\r \x{85}\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}`

// Quoted '/abs', quoted "/abs" without $, or a bare /abs after whitespace or at the start. The same pattern as
// Node inventory.
var scriptPathPattern = regexp.MustCompile(`'(/[^']+)'|"(/[^"$]+)"|(?:^|[` + spaceRanges + `])(/[^` + spaceRanges + `'";|&)]+)`)

var scriptExtensions = []string{"sh", "bash", "zsh", "js", "mjs", "cjs", "ts", "py", "rb"}

// ScriptPaths are the absolute script paths a hook command points at, in order of first appearance. A command
// is dead only when it names at least one script path and none of them exists any more. The command is never
// executed (S-R4). The result is never nil.
func ScriptPaths(command string) []string {
	found := []string{}
	for _, m := range scriptPathPattern.FindAllStringSubmatch(command, -1) {
		path := ""
		for _, group := range m[1:] {
			if group != "" {
				path = group
				break
			}
		}
		if path == "" || slices.Contains(found, path) {
			continue
		}
		for _, ext := range scriptExtensions {
			if strings.HasSuffix(path, "."+ext) {
				found = append(found, path)
				break
			}
		}
	}
	return found
}
