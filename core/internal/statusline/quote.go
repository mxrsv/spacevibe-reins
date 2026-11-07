package statusline

import (
	"path"
	"strings"
)

// Quote is text as one POSIX shell word: single quotes, with each embedded quote written as '\”.
func Quote(text string) string { return "'" + strings.ReplaceAll(text, "'", `'\''`) + "'" }

// maxUnwrap bounds how many nested wrappers unwrap removes. It also heals a command that an older build wrapped
// twice; a longer chain is not something SpaceVibe wrote.
const maxUnwrap = 8

// words splits command into the words Quote produces, joined by single spaces: quoted segments, \' and bare
// letters, digits and "_-./". Anything else (an operator, a variable, a second space) is not text SpaceVibe wrote, so
// the result is false and the caller treats the command as the user's own.
func words(command string) ([]string, bool) {
	var out []string
	for i := 0; i < len(command); {
		var word strings.Builder
		start := i
		for i < len(command) && command[i] != ' ' {
			switch c := command[i]; {
			case c == '\'':
				end := strings.IndexByte(command[i+1:], '\'')
				if end < 0 {
					return nil, false
				}
				word.WriteString(command[i+1 : i+1+end])
				i += end + 2
			case c == '\\' && i+1 < len(command) && command[i+1] == '\'':
				word.WriteByte('\'')
				i += 2
			case c >= '0' && c <= '9' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || strings.IndexByte("_-./", c) >= 0:
				word.WriteByte(c)
				i++
			default:
				return nil, false
			}
		}
		if i == start {
			return nil, false // a leading or doubled space
		}
		out = append(out, word.String())
		if i < len(command) {
			i++
			if i == len(command) {
				return nil, false // a trailing space
			}
		}
	}
	return out, len(out) > 0
}

// collector reports whether word is <dir>/bin/<name> as an absolute path.
func collector(word, name string) bool {
	return path.IsAbs(word) && path.Base(word) == name && path.Base(path.Dir(word)) == "bin"
}

// unwrapOnce returns the command a SpaceVibe wrapper delegates to. It knows both spellings, whatever data folder
// they name (G-fix.19: the Swift check looked only for its own prefix, so a moved data root wrapped twice):
//
//	'<dir>/bin/reins-statusline' --capture '<data>' '<claude>' '<original>'            (the Swift collector)
//	'<dir>/bin/spacevibe' statusline capture '<data>' '<claude>' '<original>'
func unwrapOnce(command string) (string, bool) {
	w, ok := words(command)
	if !ok {
		return "", false
	}
	switch {
	case len(w) == 6 && collector(w[0], "spacevibe") && w[1] == "statusline" && w[2] == cmdCapture &&
		path.IsAbs(w[3]) && path.IsAbs(w[4]):
		return w[5], true
	case len(w) == 5 && collector(w[0], "reins-statusline") && w[1] == "--capture" &&
		path.IsAbs(w[2]) && path.IsAbs(w[3]):
		return w[4], true
	}
	return "", false
}

// unwrap removes every SpaceVibe wrapper around command and returns what the user's own status line runs.
func unwrap(command string) string {
	for range maxUnwrap {
		inner, ok := unwrapOnce(command)
		if !ok {
			break
		}
		command = inner
	}
	return command
}
